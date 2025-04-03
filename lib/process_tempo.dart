import 'dart:collection';
import 'dart:math';

import 'package:bsteele_music_lib/songs/music_constants.dart';
import 'package:logger/logger.dart';

import 'app_logger.dart';
import 'audio_configuration.dart';
import 'bsteele_music_tempo.dart';

const Level _logDetail = Level.debug;

const _confirmations = 2;
const samplePeriodUs = Duration.microsecondsPerSecond / sampleRate;
double lastEpochUs = 0;

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
          _maxAbs = 0;
          _minAbs = audioConfiguration.ampMaximum;
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
            print(
              'hertz: '
              ' ${((1 + _looseTolerance) * MusicConstants.minBpm) / (60 * _beatsPerMeasure)}'
              ' <= $_lastHertz'
              ' <= ${((1 - _looseTolerance) * MusicConstants.maxBpm) / 60}',
            );
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
              print(
                'out of hertz range: ${_lastHertz.toStringAsFixed(3)}'
                ' @ ${audioConfiguration.debugAmp(_maxAbs)}',
              );
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
        _maxAbs = max(_maxAbs, abs);
        _minAbs = min(_minAbs, abs);
        break;
    }

    _samplesInState++;

    //  something has stalled... or there is no signal
    if (_samplesInState > 6 * sampleRate) {
      print(
        '${DateTime.now()}: $_samplesInState: stalled'
        ' @${audioConfiguration.debugAmp(_minAbs)} <= ${audioConfiguration.debugAmp(_minAbs)}'
        ', from ${audioConfiguration.debugAmp(minSignalAmp)} < 1.0',
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

    _tapUs.add(epochUs);

    if (_tapUs.length > 1) {
      print('deltaUs: ${_tapUs.elementAt(1) - _tapUs.first}');
    }

    //  find the max tempo delta
    int maxDeltaUs = -1;
    int periodUs = 1;
    if (_tapUs.length > 1 + _confirmations) {
      int nextElement = _tapUs.elementAt(1);
      int lastElement = _tapUs.first;
      periodUs = nextElement - lastElement;
      maxDeltaUs = periodUs;
      lastElement = nextElement;
      // if (veryVerbose) {
      //   print(
      //     '$greekLambda: ${(periodUs / Duration.microsecondsPerSecond).toStringAsFixed(3)} s'
      //     ' = ${(Duration.microsecondsPerSecond / periodUs).toStringAsFixed(3)} hz'
      //     ' = $bestBpm bpm',
      //   );
      // }

      for (var i = 2; i < _tapUs.length; i++) {
        nextElement = _tapUs.elementAt(i);
        int nextPeriodUs = nextElement - lastElement;
        int deltaUs = (nextPeriodUs - periodUs).abs();
        maxDeltaUs = max(maxDeltaUs, deltaUs);
        print('deltaUsAtIndex($i): $deltaUs/$maxDeltaUs, period: $nextPeriodUs vs $periodUs');
        lastElement = nextElement;
      }
    }

    //  find the taps per measure
    tapsPerMeasure = (_expectedMeasurePeriodUs / periodUs).round();
    //print('tapsPerMeasure: $tapsPerMeasure = ${_expectedMeasurePeriodUs / periodUs}');
    tapsPerMeasure = min(tapsPerMeasure, _beatsPerMeasure);

    //  insist on reasonable tap multiples: 1, 2, or beats per measure
    if (tapsPerMeasure < _beatsPerMeasure && tapsPerMeasure != 1) {
      //  tapping 3 out of 4 or 3 over 6 beats doesn't work
      switch (_beatsPerMeasure) {
        case 3:
          tapsPerMeasure = 1;
          break;
        default:
          tapsPerMeasure = 2;
          break;
      }
    }
    print('tapsPerMeasure: $tapsPerMeasure');

    //  deliver the result if valid
    if (maxDeltaUs >= 0 &&
        maxDeltaUs <
            _expectedMeasurePeriodUs /
                tapsPerMeasure //  fewer taps implies more tolerance
                *
                (1 + _tightTolerance)) {
      bestBpm = (60 * Duration.microsecondsPerSecond * _beatsPerMeasure / (tapsPerMeasure * periodUs)).round();

      // notify of a new value
      callback?.call();

      if (veryVerbose) {
        print(
          '${DateTime.now()}:'
          ' $greekCapitalDelta: ${(maxDeltaUs / Duration.microsecondsPerSecond).toStringAsFixed(3)} s'
          ', amp: ${audioConfiguration.debugAmp(_instateMaxAmp)}'
          //  tpm = taps per measure
          ', tpm: $tapsPerMeasure'
          ', Q: ${_tapUs.length}'
          //'$_tapUs'
          // ', Qs: ${(_expectedMeasurePeriodUs/ Duration.microsecondsPerSecond).toStringAsFixed(3)}'
          ', Qmax: ${((_confirmations * _expectedMeasurePeriodUs * (1 + _tightTolerance)) / Duration.microsecondsPerSecond).toStringAsFixed(3)}'
          ', $greekLambda:'
          ' ${(periodUs / Duration.microsecondsPerSecond).toStringAsFixed(3)} s'
          ' = ${(Duration.microsecondsPerSecond / periodUs).toStringAsFixed(3)} hz'
          ' = $bestBpm bpm',
        );
      }
    } else {
      print(
        'delta: $maxDeltaUs: out of bounds, tapsPerMeasure: $tapsPerMeasure'
        ' , taps: ${_tapUs.length}'
        ' , limit: ${_expectedMeasurePeriodUs / tapsPerMeasure * (1 + _tightTolerance)}',
      );
    }

    //  toss stale samples
    while ((_tapUs.last - _tapUs.first) > _confirmations * _expectedMeasurePeriodUs
    // * (1 + _tightTolerance)
    ) {
      _tapUs.removeFirst();
    }
    // print('_tapUs: ${_tapUs.length}'
    //     ', $_confirmations * $_expectedMeasurePeriodUs');
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
  final Queue<int> _tapUs = Queue();

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
    _looseTolerance = _beatsPerMeasure < 6 ? _looseTolerance234 : _looseTolerance6;
    _computeExpectedPeriodUs();
  }

  _computeExpectedPeriodUs() {
    _expectedMeasurePeriodUs = (_beatsPerMeasure * Duration.microsecondsPerSecond * 60) ~/ _expectedBpm;
  }

  // _clearExpectedPeriodUs() {
  //   _expectedMeasurePeriodUs = 1;
  // }
  //
  // _expectedPeriodUsIsValid() {
  //   return _expectedMeasurePeriodUs > 1;
  // }

  static const defaultBpm = 120;
  int _expectedBpm = defaultBpm;

  int get beatsPerMeasure => _beatsPerMeasure;
  int _beatsPerMeasure = 4; //  default only value
  int bestBpm = 0;
  int tapsPerMeasure = 0;
  int _expectedMeasurePeriodUs = 1;

  double get hertz => _lastHertz;
  double _lastHertz = 0;

  bool verbose = false;
  bool veryVerbose = false;

  VoidCallback? callback; //  callback on valid data, i.e. a new bpm

  static const _tightTolerance = 0.095; //  the operator has to be regular... or we'll follow junk tempos
  static const _looseTolerance234 = 0.3; //  worry about every beat tap & accepting a short period
  static const _looseTolerance6 = 0.16; //  worry about 6 beats per bar being misunderstood.
  double _looseTolerance = _looseTolerance234;

  static const _minimumHertz = 40;
  static const int _hysteresisMinimumSamples = sampleRate ~/ _minimumHertz;
}
