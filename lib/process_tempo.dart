import 'dart:collection';
import 'dart:math';

import 'package:bsteele_music_lib/songs/music_constants.dart';
import 'package:bsteele_music_tempo/util.dart';
import 'package:logger/logger.dart';

import 'app_logger.dart';
import 'audio_configuration.dart';
import 'bsteele_music_tempo.dart';

const Level _logDetail = Level.debug;
// const Level _logTapUsRemove = Level.debug;

const _confirmations = 2;
const _samplePeriodUs = Duration.microsecondsPerSecond / sampleRate;
double _lastEpochUs = 0;

const String greekCapitalDelta = '\u0394';
const String greekLambda = '\u03bb';

typedef VoidCallback = void Function();

class ProcessTempo {
  ProcessTempo() {
    //  default setup to run without supervision
    expectedBpm = defaultBpm;
    beatsPerMeasure = 4; //  default only
  }

  processNewTempo(final int value, {double? epochUs}) {
    epochUs ??= _lastEpochUs + _samplePeriodUs;
    _lastEpochUs = epochUs;

    //  note that this doubles the hysteresis minimum samples possibilities
    final int absAmp = value.abs(); //  negative amplitude is still amplitude

    switch (isSignal) {
      case true:
        if (absAmp > minSignalAmp) {
          _lastSignalCount = 0;
        } else {
          _lastSignalCount++;
        }
        _instateMaxAmp = max(_instateMaxAmp, absAmp);
        if (absAmp < minSignalAmp && _lastSignalCount > _hysteresisMinimumSamples) {
          isSignal = false;
          _samplesNotInstateCount = 0;
          _samplesNotInstateSum = 0;
          _maxAbs = 0;
          _minAbs = audioConfiguration.ampMaximum;
        }
        break;
      case false:
        if (absAmp >= minSignalAmp && _samplesInState > 0) {
          //  first signal up is the mark
          isSignal = true;

          if (!_isFirst) {
            //  exclude out bad tempos
            _lastHertz = sampleRate / _samplesInState;
            //  note that a slow tempo can be expected, eg. a 4/4 song at 50 bpm with beats on 2 only
            //  or as fast as every beat
            logger.log(
              _logDetail,
              'hertz: '
              ' ${((1 - _looseTolerance) * MusicConstants.minBpm) / (60 * _beatsPerMeasure)}'
              ' <= $_lastHertz'
              ' <= ${((1 + _looseTolerance) * MusicConstants.maxBpm) / 60}',
            );
            if (_lastHertz >= ((1 - _looseTolerance) * MusicConstants.minBpm) / (60 * _beatsPerMeasure) &&
                _lastHertz <= ((1 + _looseTolerance) * _expectedBpm) / 60) {
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
              if (veryVerbose) {
                print(
                  'out of hertz range: ${_lastHertz.toStringAsFixed(3)} hz'
                  ' = ${to3(60 * _lastHertz)} bpm'
                  ' @  ${audioConfiguration.debugAmp(_instateMaxAmp)}',
                );
              }
            }
          }

          _isFirst = false;
          _samplesInState = 0;
          _lastSignalCount = 0;
          _samplesNotInstateSum = 0;
          _samplesNotInstateCount = 0;
          _instateMaxAmp = absAmp;
          break;
        }
        _samplesNotInstateSum += absAmp;
        _samplesNotInstateCount++;
        _maxAbs = max(_maxAbs, absAmp);
        _minAbs = min(_minAbs, absAmp);
        break;
    }

    _samplesInState++;

    //  something has stalled... or there is no signal
    if (_samplesInState > 6 * sampleRate) {
      print(
        '${DateTime.now()}: $_samplesInState: stalled'
        ' @ ${audioConfiguration.debugAmp(_maxAbs)}'
      );

      _samplesInState = 3 * sampleRate; //  something too slow
      _lastSamplesInState = 0;
      _maxAbs = 0;
      _minAbs = audioConfiguration.ampMaximum;
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
        ' = ${((epochUs - _tapUs.last) / Duration.microsecondsPerSecond).toStringAsFixed(3)} s',
      );
      // if ( verbose ){
      //   print(
      //       'delta: $epochUs: ${epochUs - _tapUs.last} us'
      //           ' = ${((epochUs - _tapUs.last) / Duration.microsecondsPerSecond).toStringAsFixed(3)} s');
      // }
    }

    int periodUs = epochUs - _lastPeiodStartUs;
    _lastPeiodStartUs = epochUs;

    //  if it's been too long, eliminate stale data
    if (periodUs > _expectedMeasurePeriodUs * (1 + _confirmations) * (1 + _looseTolerance)) {
      _tapUs.clear();
      _beatQueueUs.clear();
      return;
    }

    //  remember when the last tap was
    _tapUs.add(epochUs);

    //  figure out how many beats have there been since the prior tap
    int beats = (periodUs / _expectedBeatPeriodUs).round();
    beats = max(1, beats);

    //  remember the average beat duration between taps
    var beatUs = periodUs / beats;
    _beatQueueUs.add(beatUs);

    //  see if we have enough taps to average
    if (_beatQueueUs.length >= _confirmations) {
      double sum = 0;
      for (double p in _beatQueueUs) {
        sum += p;
      }
      double averageUs = sum / _beatQueueUs.length;
      // print('averageUs: $averageUs');

      //  see if the taps are consistent with each other
      bool consistent = true;
      for (double p in _beatQueueUs) {
        // print('  ($p - $averageUs).abs() = ${(p -averageUs).abs()}  vs: ${averageUs * _tightTolerance}');
        if ((p - averageUs).abs() > averageUs * _tightTolerance) {
          //  failed
          consistent = false;
          break;
        }
      }
      if (consistent) {
        bestBpm = (60 * Duration.microsecondsPerSecond / averageUs).round();

        // notify of a new value
        callback?.call();
      }
    }

    if (veryVerbose && periodUs > 0) {
      print(
        '${DateTime.now()}: '
        '@ ${to3(_instateMaxAmp / audioConfiguration.ampMaximum)}'
        ', ${to3(periodUs / Duration.microsecondsPerSecond)} s / $beats = ${to3(Duration.microsecondsPerSecond / beatUs)} hz'
        ' = ${to3(60 * Duration.microsecondsPerSecond / beatUs)} bpm',
      );
    }

    //  toss stale samples
    while (_tapUs.length > (1 + _confirmations)) {
      _tapUs.removeFirst();
    }
    while (_beatQueueUs.length > _tapUs.length) {
      _beatQueueUs.removeFirst();
    }
    logger.log(
      _logDetail,
      '_tapUs: ${_tapUs.length}'
      ', $_confirmations * $_expectedMeasurePeriodUs'
      ' vs ${_tapUs.last - _tapUs.first} = ${(_tapUs.last - _tapUs.first) / (_confirmations * _expectedMeasurePeriodUs)}',
    );
    logger.log(_logDetail, '    _tapUs:  $_tapUs');
    logger.log(_logDetail, '    _beatUs: $_beatQueueUs');
  }

  @override
  String toString() {
    return '$isSignal for $_samplesInState, lastHertz: ${_lastHertz.toStringAsFixed(3)}'
        ', expectedBpm: $_expectedBpm, beatsPerMeasure: $_beatsPerMeasure';
  }

  int minSignalAmp = (audioConfiguration.ampMaximum * 0.045).toInt();
  bool isSignal = false;
  bool _isFirst = true;
  int _samplesInState = 0;
  int _lastSamplesInState = 0;

  bool get isConsistent => _consistent;
  bool _consistent = false;
  int _lastSignalCount = 0;
  int _samplesNotInstateCount = 0;
  int _samplesNotInstateSum = 0;
  int _lastPeiodStartUs = 0;
  final Queue<int> _tapUs = Queue();
  final Queue<double> _beatQueueUs = Queue();

  int get instateMaxAmp => _instateMaxAmp;
  int _instateMaxAmp = 0;

  double get maxAmp => _maxAbs / audioConfiguration.ampMaximum;
  int _maxAbs = 0;
  int _minAbs = audioConfiguration.ampMaximum;

  double get samplesNotInstateAverage => _samplesNotInstateAverage;
  double _samplesNotInstateAverage = 0;

  set expectedBpm(final int givenBpm) {
    _expectedBpm = givenBpm >= MusicConstants.minBpm ? givenBpm : defaultBpm;
    _computeExpectedPeriodUs();
  }

  set beatsPerMeasure(final int beats) {
    _beatsPerMeasure = beats < 2 ? 2 : beats;
    _computeExpectedPeriodUs();
  }

  _computeExpectedPeriodUs() {
    _expectedBeatPeriodUs = (Duration.microsecondsPerSecond * 60) ~/ _expectedBpm;
    _expectedMeasurePeriodUs = _beatsPerMeasure * _expectedBeatPeriodUs;
  }

  static const defaultBpm = 120;
  int _expectedBpm = defaultBpm;

  int get beatsPerMeasure => _beatsPerMeasure;
  int _beatsPerMeasure = 4; //  default only value
  int bestBpm = 0;
  int tapsPerMeasure = 0;
  int _expectedMeasurePeriodUs = 1;
  int _expectedBeatPeriodUs = 1;

  double get hertz => _lastHertz;
  double _lastHertz = 0;

  bool verbose = false;
  bool veryVerbose = false;

  VoidCallback? callback; //  callback on valid data, i.e. a new bpm

  static const _tightTolerance = 0.095; //  the operator has to be regular... or we'll follow junk tempos
  static const _looseTolerance = 0.3;

  static const _minimumHertz = 40;
  static const int _hysteresisMinimumSamples = sampleRate ~/ _minimumHertz;
}
