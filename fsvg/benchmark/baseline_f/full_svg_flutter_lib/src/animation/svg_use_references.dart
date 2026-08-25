/// Shared `<use>` reference semantics for rendering-related SVG paths.
///
/// Keep these definitions shared by painting, hit testing, and async filter
/// precomputation so they all traverse the same rendered `<use>` graph.
const int maxSvgUseRecursionDepth = 10;

/// Whether [tagName] is an element type that this renderer permits a `<use>`
/// element to reference.
bool isSvgUseReferenceAllowedTag(String tagName) {
  switch (tagName) {
    case 'a':
    case 'circle':
    case 'desc':
    case 'ellipse':
    case 'g':
    case 'image':
    case 'line':
    case 'metadata':
    case 'path':
    case 'polygon':
    case 'polyline':
    case 'rect':
    case 'svg':
    case 'switch':
    case 'symbol':
    case 'text':
    case 'textPath':
    case 'title':
    case 'tref':
    case 'tspan':
    case 'use':
      return true;
    default:
      return false;
  }
}
