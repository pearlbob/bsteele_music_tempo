import 'dart:math';

// import 'package:logger/logger.dart';

import 'audio_configuration.dart';

// const Level _logSummary = Level.debug;

typedef VoidCallback = void Function();

class ProcessTempo {
  processTempo(final int value) {
    //  note that this doubles the hysteresis minimum samples possibilities
    final int abs = value.abs(); //  negative amplitude is still amplitude

    switch (isSignal) {
      case true:
        if (abs > minSignalAmp) {
          _lastSignalCount = 0;
        } else {
          _lastSignalCount++;
        }
        _instateMaxAmp = max(_instateMaxAmp, abs);
        if (abs < minSignalAmp && _lastSignalCount > _hysteresisMinimumSamples) {
          isSignal = false;
          _samplesNotInstateCount = 0;
          _samplesNotInstateSum = 0;
        }
        break;
      case false:
        if (abs >= minSignalAmp && _samplesInState > 0) {
          //  first signal up is the mark
          isSignal = true;

          if (!_isFirst) {
            //  exclude out bad tempos
            _lastHertz = sampleRate / _samplesInState;
            //  note that a slow tempo can be expected, eg. a 4/4 song at 50 bpm with beats on 2 and 4 only
            if (_lastHertz >= 22 / 60 && _lastHertz <= 200 / 60) {
              if (_samplesNotInstateCount > 0) {
                _samplesNotInstateAverage = _samplesNotInstateSum / _samplesNotInstateCount;
              }

              _consistent = (_samplesInState - _lastSamplesInState).abs() < (_samplesInState * 0.08);
              print('${DateTime.now()}: $_samplesInState'
                  ' = ${(_samplesInState / sampleRate).toStringAsFixed(3).padLeft(6)}s'
                  ' = ${_lastHertz.toStringAsFixed(3).padLeft(6)} hz'
                  ' = ${(60.0 * _lastHertz).toStringAsFixed(3).padLeft(6)} bpm'
                  ' @ ${_instateMaxAmp.toString().padLeft(5)}, consistent: $_consistent' );

              // notify of a new value
              callback?.call();

              _lastSamplesInState = _samplesInState;
            }
          }

          _isFirst = false;
          _samplesInState = 0;
          _lastSignalCount = 0;
          _samplesNotInstateSum = 0;
          _samplesNotInstateCount = 0;
          _instateMaxAmp = abs;
          break;
        }
        _samplesNotInstateSum += abs;
        _samplesNotInstateCount++;
        break;
    }

    _samplesInState++;

    //  something has stalled... or there is no signal
    if (_samplesInState > 6 * sampleRate) {
      print('${DateTime.now()}: $_samplesInState: stalled @ $abs');
      _samplesInState = 3 * sampleRate; //  something too slow
      _lastSamplesInState = 0;
    }
  }

  @override
  String toString() {
    return '$isSignal for $_samplesInState, lastHertz: $_lastHertz';
  }

  static const minSignalAmp = ampMaximum * 0.045;
  bool isSignal = false;
  bool _isFirst = true;
  int _samplesInState = 0;
  int _lastSamplesInState = 0;

  bool get isConsistent => _consistent;
  bool _consistent = false;
  int _lastSignalCount = 0;
  int _samplesNotInstateCount = 0;
  int _samplesNotInstateSum = 0;

  int get instateMaxAmp => _instateMaxAmp;
  int _instateMaxAmp = 0;

  double get samplesNotInstateAverage => _samplesNotInstateAverage;
  double _samplesNotInstateAverage = 0;

  int get bpm => (_lastHertz * 60.0).round();

  double get hertz => _lastHertz;
  double _lastHertz = 0;

  VoidCallback? callback; //  callback on valid data, i.e. a new bpm

  static const _minimumHertz = 40;
  static const int _hysteresisMinimumSamples = sampleRate ~/ _minimumHertz;
}
