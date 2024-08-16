import 'dart:collection';
import 'dart:math';

import 'package:bsteele_music_lib/songs/music_constants.dart';
import 'package:logger/logger.dart';

import 'app_logger.dart';
import 'audio_configuration.dart';

const Level _logDetail = Level.debug;

const _confirmations = 2;
const samplePeriodUs = Duration.microsecondsPerSecond / sampleRate;
final _maxError = double.maxFinite.toInt();
double lastEpochUs = 0;

typedef VoidCallback = void Function();

class ProcessTempo {
  ProcessTempo() {
    //  default setup to run without supervision
    expectedBpm = defaultBpm;
    beatsPerMeasure = 4;
  }

  processNewTempo(final int value, {double? epochUs}) {
    epochUs ??= lastEpochUs + samplePeriodUs;
    lastEpochUs = epochUs;

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
            // print( 'hertz: '
            //     ' ${((1 + _looseTolerance) * MusicConstants.minBpm) / (60 * _beatsPerMeasure)}'
            //     ' <= $_lastHertz'
            //     ' <= ${((1 - _looseTolerance) * MusicConstants.maxBpm) / 60 }');
            if (_lastHertz >= ((1 + _looseTolerance) * MusicConstants.minBpm) / (60 * _beatsPerMeasure) &&
                _lastHertz <= ((1 - _looseTolerance) * MusicConstants.maxBpm) / 60) {
              if (_samplesNotInstateCount > 0) {
                _samplesNotInstateAverage = _samplesNotInstateSum / _samplesNotInstateCount;
              }

              _processTempoTap(epochUs.toInt());

              _consistent = (_samplesInState - _lastSamplesInState).abs() < (_samplesInState * _tightTolerance);

              // if (verbose) {
              //   print('${DateTime.now()}: $_samplesInState'
              //       ' = ${(_samplesInState / sampleRate).toStringAsFixed(3).padLeft(6)}s'
              //       ' = ${_lastHertz.toStringAsFixed(3).padLeft(6)} hz'
              //       ' = ${(60.0 * _lastHertz).toStringAsFixed(3).padLeft(6)} bpm'
              //       ' @ ${_instateMaxAmp.toString().padLeft(5)}'
              //       ', perBar: $_beatsPerMeasure'
              //       ', _expectedBpm: $_expectedBpm'
              //       ', consistent: $_consistent'
              //       // ', maxDelta: $_maxDeltaUs us'
              //       );
              // }

              _lastSamplesInState = _samplesInState;
            } else {
              print('out of hertz range: $_lastHertz');
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

    // if (_tapUs.length > 1) {
    //   print('${_tapUs.elementAt(1) - _tapUs.first}');
    // }

    //  find the best fit for the first sample
    // print('_processSample($epochUs):  length: ${_tapUs.length}');
    int maxErrorUs = _maxError;
    int bestIndex = -1;
    int bestPeriodUs = -1;
    for (var i = 1; i < _tapUs.length - _confirmations; i++) {
      int errorUs = _tapErrorUsAtIndex(i);
      // print('_tapErrorUsAtIndex($i): $errorUs');
      if (errorUs < maxErrorUs) {
        bestIndex = i;
        bestPeriodUs = _periodUs;
        maxErrorUs = errorUs;
      }
    }
    if (bestIndex > 0) {
      bestBpm = ((60 * Duration.microsecondsPerSecond * _beatsPerMeasure) / bestPeriodUs).round();
      // if (verbose) {
      //   print('bestBpm: ${(60 * Duration.microsecondsPerSecond * _beatsPerMeasure) / bestPeriodUs}'
      //       ', _beatsPerMeasure: $_beatsPerMeasure'
      //       ', bestPeriodUs: $bestPeriodUs'
      //       ', bestIndex: $bestIndex'
      //       ', maxErrorUs: $maxErrorUs'
      //       ', _expectedMeasurePeriodUs: $_expectedMeasurePeriodUs');
      // }

      // notify of a new value
      callback?.call();

      if (verbose) {
        print('   bestIndex: $bestIndex, error: ${maxErrorUs.toString().padLeft(6)}'
            ', beatsPerMeasure: $_beatsPerMeasure'
            ', bestPeriodUs: $bestPeriodUs/$_expectedMeasurePeriodUs = $bestBpm bpm');
      }
      // print('delta: $epochUs: ${epochUs - _tapUs.last} us'
      //     ' = ${((epochUs - _tapUs.last) / Duration.microsecondsPerSecond).toStringAsFixed(3)} s');
    }

    //  toss stale samples
    while ((_tapUs.last - _tapUs.first) > _confirmations * _expectedMeasurePeriodUs * (1 + _looseTolerance)) {
      _tapUs.removeFirst();
    }
    // print('_tapUs: ${_tapUs.length}'
    //     ', $_confirmations * $_expectedMeasurePeriodUs');
  }

  int _tapErrorUsAtIndex(final int index) {
    //  reject obviously bad conditions
    if (index < 1 || index >= _tapUs.length || _tapUs.length < _confirmations + 1) {
      return _maxError;
    }

    //  compute the implied period in us
    final int firstUs = _tapUs.first;
    _periodUs = _tapUs.elementAt(index) - firstUs;
    // print('$index: $_periodUs/$_expectedMeasurePeriodUs'
    //     ' = ${_periodUs/_expectedMeasurePeriodUs}');
    if (_periodUs <= 0) {
      return _maxError; //  should never happen
    }

    //  see if the implied period is roughly sane
    if (_expectedPeriodUsIsValid()) {
      if (_periodUs < _expectedMeasurePeriodUs * (1.0 - _looseTolerance)) {
        // print( 'too fast: $_periodUs < $_expectedMeasurePeriodUs * ${(1.0 - _looseTolerance)}');
        return _maxError;
      }
      if (_periodUs > _expectedMeasurePeriodUs * (1.0 + _looseTolerance)) {
        // print( 'too slow: $_periodUs < $_expectedMeasurePeriodUs * ${(1.0 + _looseTolerance)}');
        return _maxError;
      }
    } else {
      return _maxError;
    }

    //  try to find this period in the data
    int count = 1;
    int maxErrorFound = 0;
    int errorLimitUs = (_tightTolerance * _periodUs).floor().toInt();
    int target = firstUs + (count + 1) * _periodUs;
    int beats = 1;
    for (int i = index + 1;
        i < _tapUs.length //  only look at existing data
            &&
            count < _confirmations; //  don't need more than the minimum confirmations
        i++) {

      //  compute the tempo error
    int  tapElementUs = _tapUs.elementAt(i);
      final int errorUs = tapElementUs - target;

      // print( 'errorUs $i: ${-errorLimitUs} < $errorUs < $errorLimitUs');
      if (errorUs < -errorLimitUs) {
        beats++;
        continue; //  too early
      } else if (errorUs > errorLimitUs) {
        //  too late now, will never get better, not this pass!
        return _maxError;
      }
      //  record the roughest match
      if (errorUs.abs() > maxErrorFound) {
        maxErrorFound = errorUs.abs();
      }

      //  break if we've seen too many attempts, i.e. beats per bar or more
      if ( beats > _beatsPerMeasure ){
        break;
      }

      //  increment for next match
      count++;
      target = firstUs + (count + 1) * _periodUs;
      beats = 1;
    }

    if (maxErrorFound > errorLimitUs) {
      return maxErrorFound;
    }

    //  return the max passing error... or a failure max error
    return count < _confirmations ? _maxError : maxErrorFound;
  }

  @override
  String toString() {
    return '$isSignal for $_samplesInState, lastHertz: ${_lastHertz.toStringAsFixed(3)}'
        ', expectedBpm: $_expectedBpm, beatsPerMeasure: $_beatsPerMeasure';
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
    _looseTolerance = _beatsPerMeasure < 6 ? _looseTolerance234 : _looseTolerance6;
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

  bool verbose = false;

  VoidCallback? callback; //  callback on valid data, i.e. a new bpm

  static const _tightTolerance = 0.08; //  the operator has to be regular... or we'll follow junk tempos
  static const _looseTolerance234 = 0.19; //  worry about every beat tap & accepting a short period
  static const _looseTolerance6 = 0.16; //  worry about 6 beats per bar being misunderstood.
  double _looseTolerance = _looseTolerance234;

  static const _minimumHertz = 40;
  static const int _hysteresisMinimumSamples = sampleRate ~/ _minimumHertz;
}
