/// 判断 CSS 语法空白：空格、制表、换行、回车、换页。
bool isCssSpace(int c) => c == 32 || c == 9 || c == 10 || c == 13 || c == 12;

/// 判断标识符里不需要转义的字符：字母、数字、`-`、`_` 与非 ASCII 字符。
bool isCssNameChar(int c) =>
    c >= 128 ||
    c == 45 ||
    c == 95 ||
    (c >= 48 && c <= 57) ||
    (c >= 65 && c <= 90) ||
    (c >= 97 && c <= 122);

/// 返回十六进制数位的值，非法字符返回负数。
int cssHexValue(int c) {
  if (c >= 48 && c <= 57) return c - 48;
  if (c >= 65 && c <= 70) return c - 65 + 10;
  if (c >= 97 && c <= 102) return c - 97 + 10;
  return -1;
}
