const sampleRate = 48000;
const channels = 2;

class AudioConfiguration {
  AudioConfiguration(this.bitDepthBytes);

  final int bitDepthBytes;

  int get bitDepth => bitDepthBytes * 8;

  int get ampMaximum => (1 << (bitDepth - 1)) - 1;

  String debug(final int v){
    return (v/ampMaximum).toStringAsFixed(3);
  }
}
