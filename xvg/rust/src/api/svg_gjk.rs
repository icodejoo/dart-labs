// Convex hull and GJK adapted from OXVG v0.0.10.
// https://github.com/noahbald/oxvg/blob/v0.0.10/crates/oxvg_path/src/gjk_intersection.rs
// MIT License
//
// Copyright (c) 2024-present noahbald
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

/// Picture-space point widened from the wire's f32 coordinates. / 从线上 f32 坐标扩展精度的 Picture 坐标点。
#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) struct Point {
    /// Horizontal coordinate. / 横坐标。
    pub x: f64,
    /// Vertical coordinate. / 纵坐标。
    pub y: f64,
}

impl Point {
    /// Computes a direction projection. / 计算在指定方向上的投影。
    fn dot(self, other: Self) -> f64 {
        self.x * other.x + self.y * other.y
    }

    /// Returns the perpendicular facing away from the given vector. / 返回背离给定向量的垂线。
    fn orth(self, other: Self) -> Self {
        let normal = Self {
            x: -self.y,
            y: self.x,
        };
        if normal.dot(other) > 0.0 {
            -normal
        } else {
            normal
        }
    }

    /// Computes the turn from AB to AC. / 计算 AB 到 AC 的转向。
    fn cross(a: Self, b: Self, c: Self) -> f64 {
        let ab = b - a;
        let ac = c - a;
        ab.x * ac.y - ab.y * ac.x
    }
}

impl std::ops::Sub for Point {
    type Output = Self;

    fn sub(self, other: Self) -> Self {
        Self {
            x: self.x - other.x,
            y: self.y - other.y,
        }
    }
}

impl std::ops::Neg for Point {
    type Output = Self;

    fn neg(self) -> Self {
        Self {
            x: -self.x,
            y: -self.y,
        }
    }
}

/// Builds OXVG's monotone-chain hull using every endpoint and Bézier control point. / 用所有端点及贝塞尔控制点构建 OXVG 单调链凸包。
pub(super) fn convex_hull(mut source: Vec<Point>) -> Vec<Point> {
    source.sort_unstable_by(|a, b| {
        // Numerically equal x coordinates must share the same vertical sort. / 数值相同的横坐标使用同一个纵向排序。
        if a.x == b.x {
            a.y.total_cmp(&b.y)
        } else {
            a.x.total_cmp(&b.x)
        }
    });
    source.dedup();
    if source.len() <= 2 {
        return source;
    }
    let mut hull = Vec::with_capacity(source.len());
    for chain in [false, true] {
        let start = hull.len();
        let indices = 0..source.len();
        for i in indices {
            let point = source[if chain { source.len() - 1 - i } else { i }];
            while hull.len() >= start + 2
                && Point::cross(hull[hull.len() - 2], hull[hull.len() - 1], point) <= 0.0
            {
                hull.pop();
            }
            hull.push(point);
        }
        hull.pop();
    }
    hull
}

/// Tests Minkowski differences of hulls expanded by square margins. / 检测经正方形余量外扩的凸包的闵可夫斯基差。
pub(super) fn intersects(a: &[Point], b: &[Point], padding: f64) -> bool {
    // Linear support also handles collinear hulls and tied extrema. / 线性支撑点搜索也处理共线凸包和并列极值。
    let furthest = |hull: &[Point], direction: Point| {
        *hull
            .iter()
            .max_by(|p, q| p.dot(direction).total_cmp(&q.dot(direction)))
            .unwrap()
    };
    let support = |direction: Point| {
        // The support of a square of half-edge `padding` is a corner. / 半边长为 padding 的正方形的支撑点为其一角。
        let d = furthest(a, direction) - furthest(b, -direction);
        Point {
            x: d.x + direction.x.signum() * padding,
            y: d.y + direction.y.signum() * padding,
        }
    };
    let mut simplex = [support(Point { x: 1.0, y: 0.0 }); 3];
    let mut len = 1;
    let mut direction = -simplex[0];
    for _ in 0..32 {
        let scale = direction.x.abs().max(direction.y.abs());
        if scale == 0.0 || !scale.is_finite() {
            break;
        }
        direction = Point {
            x: direction.x / scale,
            y: direction.y / scale,
        };
        let point = support(direction);
        if direction.dot(point) < 0.0 {
            return false;
        }
        simplex[len] = point;
        len += 1;
        if process_simplex(&mut simplex, &mut len, &mut direction) {
            break;
        }
    }
    // Touching and nonconvergence both block a merge. / 相切和未能收敛都阻止合并。
    true
}

/// Reduces the OXVG simplex and selects the next search direction. / 缩减 OXVG 单纯形并选择下一搜索方向。
fn process_simplex(simplex: &mut [Point; 3], len: &mut usize, direction: &mut Point) -> bool {
    let a = simplex[*len - 1];
    let b = simplex[*len - 2];
    let ao = -a;
    let ab = b - a;
    if *len == 2 {
        if ao.dot(ab) > 0.0 {
            *direction = ab.orth(a);
        } else {
            *direction = ao;
            simplex[0] = a;
            *len = 1;
        }
        return false;
    }

    let c = simplex[0];
    let ac = c - a;
    let away_from_c = ab.orth(ac);
    let away_from_b = ac.orth(ab);
    if away_from_c.dot(ao) > 0.0 {
        if ab.dot(ao) > 0.0 {
            *direction = away_from_c;
            simplex[0] = b;
            simplex[1] = a;
            *len = 2;
            return false;
        }
    } else if away_from_b.dot(ao) > 0.0 {
        if ac.dot(ao) > 0.0 {
            *direction = away_from_b;
            simplex[1] = a;
            *len = 2;
            return false;
        }
    } else {
        return true;
    }
    *direction = ao;
    simplex[0] = a;
    *len = 1;
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Keeps both vertical extrema when the horizontal coordinates include signed zero. / 横坐标含带符号零时保留两端纵向极值。
    #[test]
    fn hull_keeps_extrema_at_signed_zero() {
        let bottom = Point { x: 0.0, y: -10.0 };
        let top = Point { x: -0.0, y: 10.0 };
        let right = Point { x: 1.0, y: 0.0 };
        let hull = convex_hull(vec![
            Point { x: -0.0, y: 0.0 },
            top,
            bottom,
            Point { x: 0.0, y: 5.0 },
            right,
        ]);
        assert_eq!(hull, [bottom, right, top]);
    }
}
