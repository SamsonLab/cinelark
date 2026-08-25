class PairingScanGate {
  bool _isHandlingCapture = false;

  bool tryBeginCapture() {
    if (_isHandlingCapture) return false;
    _isHandlingCapture = true;
    return true;
  }

  void reset() {
    _isHandlingCapture = false;
  }
}
