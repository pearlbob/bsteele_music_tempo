import 'dart:collection';
import 'dart:math';

// import 'package:logger/logger.dart';

import 'package:bsteele_music_lib/songs/music_constants.dart';
import 'package:logger/logger.dart';

import 'app_logger.dart';
import 'audio_configuration.dart';

const Level _logDetail = Level.info;


const _confirmations = 2;
final _maxError = double.maxFinite.toInt();

typedef VoidCallback = void Function();

class ProcessTempo {
  ProcessTempo() {
    _clearExpectedPeriodUs();
  }

  processNewTempo(final int value, {int? epochUs}) {
    epochUs ??= DateTime.now().microsecondsSinceEpoch;

    // if ( verbose ){
    //   print( '$epochUs: value: $value');
    // }

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
            //  note that a slow tempo can be expected, eg. a 4/4 song at 50 bpm with beats on 2 only
            //  or as fast as every beat
            if (_lastHertz >= ((1 - _looseTolerance) * MusicConstants.minBpm) / (60 * _beatsPerMeasure) &&
                _lastHertz <= ((1 + _looseTolerance) * MusicConstants.maxBpm) / 60 ) {
              if (_samplesNotInstateCount > 0) {
                _samplesNotInstateAverage = _samplesNotInstateSum / _samplesNotInstateCount;
              }

              _processTempoTap(epochUs);

              _consistent = (_samplesInState - _lastSamplesInState).abs() < (_samplesInState * _tightTolerance);

              // if (verbose) {
              //   print('${DateTime.now()}: $_samplesInState'
              //       ' = ${(_samplesInState / sampleRate).toStringAsFixed(3).padLeft(6)}s'
              //       ' = ${_lastHertz.toStringAsFixed(3).padLeft(6)} hz'
              //       ' = ${(60.0 * _lastHertz).toStringAsFixed(3).padLeft(6)} bpm'
              //       ' @ ${_instateMaxAmp.toString().padLeft(5)}, consistent: $_consistent'
              //       // ', maxDelta: $_maxDeltaUs us'
              //       );
              // }

              _lastSamplesInState = _samplesInState;
              _maxDeltaUs = 0;
            } else {
              logger.i('out of hertz range: $_lastHertz');
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
    if (_samplesInState > 16 * sampleRate) {
      print('${DateTime.now()}: $_samplesInState: stalled @ $abs, maxDelta: $_maxDeltaUs us');
      _samplesInState = 3 * sampleRate; //  something too slow
      _lastSamplesInState = 0;
      _maxDeltaUs = 0;
    }

    _maxDeltaUs = max(_maxDeltaUs, epochUs - _lastEpochUs);
    _lastEpochUs = epochUs;
  }

  /// Low level routine to sort out measure patterns in the tempo tapped.
  /// Could be every beat, every other beat, once a measure (on 2 or 4),
  /// or some other regular pattern.
  _processTempoTap(int epochUs) {
    if (_tapUs.isNotEmpty) {
      logger.log(
          _logDetail,
          'delta: $epochUs: ${epochUs - _tapUs.last} us'
          ' = ${((epochUs - _tapUs.last) / Duration.microsecondsPerSecond).toStringAsFixed(3)} s');
      // if ( verbose ){
      //   print(
      //       'delta: $epochUs: ${epochUs - _tapUs.last} us'
      //           ' = ${((epochUs - _tapUs.last) / Duration.microsecondsPerSecond).toStringAsFixed(3)} s');
      // }
    }

    _tapUs.add(epochUs);

    //  find the best fit for the first sample
    // logger.log(_logDetail,'_processSample($epochUs):  length: ${_tapUs.length}');
    int maxErrorUs = _maxError;
    int bestIndex = -1;
    int bestPeriodUs = -1;
    for (var i = 1; i < _tapUs.length - _confirmations; i++) {
      int errorUs = _tapErrorUsAtIndex(i);
      if (errorUs < _maxError) {
        bestIndex = i;
        bestPeriodUs = _periodUs;
        maxErrorUs = errorUs;
      }
    }
    if (bestIndex > 0) {
      bestBpm = (60 * Duration.microsecondsPerSecond * _beatsPerMeasure) ~/ bestPeriodUs;

      // notify of a new value
      callback?.call();

      logger.log(
          _logDetail,
          '   bestIndex: $bestIndex, error: $maxErrorUs'
          ', bestPeriodUs: $bestPeriodUs = $bestBpm bpm '
          ' vs $_expectedMeasurePeriodUs us');
      // print('delta: $epochUs: ${epochUs - _tapUs.last} us'
      //     ' = ${((epochUs - _tapUs.last) / Duration.microsecondsPerSecond).toStringAsFixed(3)} s');
    }

    //  toss stale samples
    while ((_tapUs.last - _tapUs.first) > _confirmations * _expectedMeasurePeriodUs * (1 + _looseTolerance)) {
      _tapUs.removeFirst();
    }
    // logger.i('_tapUs: ${_tapUs.length}');
  }

  int _tapErrorUsAtIndex(final int index) {
    //  reject obviously bad conditions
    if (index < 1 || index >= _tapUs.length || _tapUs.length < _confirmations + 1) return _maxError;

    //  compute the implied period in us
    _periodUs = _tapUs.elementAt(index) - _tapUs.first;
    if (_periodUs <= 0) return _maxError; //  should never happen

    //  see if the implied period is roughly sane
    if (_expectedPeriodUsIsValid()) {
      if (_periodUs < _expectedMeasurePeriodUs * (1.0 - _looseTolerance) ||
          _periodUs > _expectedMeasurePeriodUs * (1.0 + _looseTolerance)) {
        return _maxError;
      }
    }

    //  try to find this period in the data
    int count = 1;
    int maxErrorFound = 0;
    int firstUs = _tapUs.first;
    int tapUs = _tapUs.elementAt(index);
    int errorLimit = (_tightTolerance * _periodUs).floor().toInt();
    int target = firstUs + (count + 1) * _periodUs;
    for (int i = index + 1;
        i < _tapUs.length //  only look at existing data
            &&
            count < _confirmations; //  don't need more than the minimum confirmations
        i++) {
      //  compute the tempo error
      tapUs = _tapUs.elementAt(i);
      final int error = tapUs - target;

      if (error < -errorLimit) {
        continue; //  too early
      } else if (error > errorLimit) {
        //  too late now, will never get better, not this pass!
        return _maxError;
      }
      //  record the roughest match
      if (error > maxErrorFound) {
        maxErrorFound = error;
      }

      //  increment for next match
      count++;
      target = firstUs + (count + 1) * _periodUs;
    }

    //  return the max passing error... or a failure max error
    return count < _confirmations ? _maxError : maxErrorFound;
  }

  @override
  String toString() {
    return '$isSignal for $_samplesInState, lastHertz: ${_lastHertz.toStringAsFixed(3)}';
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
  final Queue<int> _tapUs = Queue();

  int get instateMaxAmp => _instateMaxAmp;
  int _instateMaxAmp = 0;

  double get samplesNotInstateAverage => _samplesNotInstateAverage;
  double _samplesNotInstateAverage = 0;

  set expectedBpm(final int givenBpm) {
    _expectedBpm = givenBpm >= MusicConstants.minBpm ? givenBpm : defaultBpm;
    _computeExpectedPeriodUs();
  }

  set beatsPerMeasure(final int beats) {
    _beatsPerMeasure = beats < 2 ? 2 : beats;
    _looseTolerance = _beatsPerMeasure < 6 ? _looseTolerance234: _looseTolerance6;
    _computeExpectedPeriodUs();
  }

  _computeExpectedPeriodUs() {
    _expectedMeasurePeriodUs = (_beatsPerMeasure * Duration.microsecondsPerSecond * 60) ~/ _expectedBpm;
  }

  _clearExpectedPeriodUs() {
    _expectedMeasurePeriodUs = 1;
  }

  _expectedPeriodUsIsValid() {
    return _expectedMeasurePeriodUs > 1;
  }

  static const defaultBpm = 120;
  int _expectedBpm = defaultBpm;
  int _beatsPerMeasure = 4; //  default only
  int bestBpm = 0;
  int _periodUs = -1;
  int _expectedMeasurePeriodUs = 1;

  double get hertz => _lastHertz;
  double _lastHertz = 0;

  int _lastEpochUs = DateTime.now().microsecondsSinceEpoch;

  int _maxDeltaUs = 0;
  bool verbose = false;

  VoidCallback? callback; //  callback on valid data, i.e. a new bpm

  static const _tightTolerance = 0.08; //  the operator has to be regular... or we'll follow junk tempos
  static const _looseTolerance234 = 0.225;//  worry about every beat tap & accepting a short period
  static const _looseTolerance6 = 0.16;
  double _looseTolerance =_looseTolerance234;

  static const _minimumHertz = 40;
  static const int _hysteresisMinimumSamples = sampleRate ~/ _minimumHertz;
}
