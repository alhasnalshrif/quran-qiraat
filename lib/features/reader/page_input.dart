int? parseMushafPage(String input, {int pageCount = 604}) {
  final normalized = String.fromCharCodes(
    input.trim().runes.map((rune) {
      if (rune >= 0x0660 && rune <= 0x0669) return rune - 0x0660 + 0x30;
      if (rune >= 0x06f0 && rune <= 0x06f9) return rune - 0x06f0 + 0x30;
      return rune;
    }),
  );
  if (!RegExp(r'^\d+$').hasMatch(normalized)) return null;
  final number = int.tryParse(normalized);
  return number != null && number >= 1 && number <= pageCount ? number : null;
}
