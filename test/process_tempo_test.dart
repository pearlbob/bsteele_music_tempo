import 'package:bsteele_music_tempo/app_logger.dart';
import 'package:bsteele_music_tempo/audio_configuration.dart';
import 'package:bsteele_music_tempo/process_tempo.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const Level _logDetail = Level.debug;
const Level _logSummary = Level.debug;

void main() {
  Logger.level = Level.info;

  // test('test process tempo', () {
  //   logger.i('test process tempo');
  //
  //   ProcessTempo processTempo = ProcessTempo();
  //
  //   processTempo.callback = () {
  //     logger.i('bpm: ${processTempo.bestBpm.toString().padLeft(3)}'
  //         ', amp: ${processTempo.instateMaxAmp.toString().padLeft(5)}'
  //         ' = x${(processTempo.instateMaxAmp/ProcessTempo.minSignalAmp).toStringAsFixed(2).padRight(5)}'
  //         ' / ${(processTempo.samplesNotInstateAverage/ProcessTempo.minSignalAmp).toStringAsFixed(3).padLeft(6)}'
  //
  //     );
  //   };
  //
  //   //  notice that the same process temp measures all of them.
  //   //  so the initial measure can be quite wrong
  //
  //   double f = 180.0; //  tone pitch
  //
  //   int maxError = 0;
  //   for (int bpm = 50 ~/ 2; bpm < 200; bpm++) {
  //     double periodS = 60 / bpm;
  //     double toneFraction = 0.15;
  //     int sampleCycle = (sampleRate * periodS).toInt();
  //     int samplesOn = (sampleCycle * toneFraction).toInt();
  //
  //     int offset = 60000;
  //     var amp = 0;
  //     const ampMax = 1 << (bitDepth - 1);
  //     const ampMin = 1;
  //     bool lastInSignal = false;
  //
  //     for (int signalMax in [ampMax, ampMax ~/ 8, ampMax ~/ 16]) {
  //       for (int sample = 0; sample < 6 * sampleRate; sample++) {
  //         int value = 0;
  //         if (sample > offset) {
  //           var index = sample - offset;
  //
  //           //  generate a pulse train every bpm
  //           amp = (index % sampleCycle < samplesOn) ? signalMax : ampMin;
  //           value = (amp * sin(2 * pi * f * index / sampleRate)).toInt();
  //         }
  //
  //         processTempo.processNewTempo(value);
  //         logger.log(
  //             _logDetail,
  //             'sample $sample: ${value.toStringAsFixed(2).padLeft(9)}'
  //             ' $processTempo');
  //
  //         if (lastInSignal != processTempo.isSignal) {
  //           lastInSignal = processTempo.isSignal;
  //           logger.log(
  //               _logSummary,
  //               'sample ${sample.toString().padLeft(9)} = ${(sample / sampleRate).toStringAsFixed(3)}s:'
  //               ' ${value.toStringAsFixed(2).padLeft(8)}'
  //               ' $processTempo');
  //         }
  //       }
  //
  //       logger.i('bpm: $bpm, signalMax: $signalMax'
  //           // ', processTempo.bpm: ${processTempo.bpm}'
  //           // ', bpm / 60: $bpm'
  //           );
  //       int error = processTempo.bestBpm - bpm;
  //       error = error.abs();
  //       logger.i('   error: $error');
  //       maxError = max(maxError, error);
  //       expect(
  //           error <= 1, //  cope with integer rounding issues
  //           isTrue);
  //     }
  //   }
  //
  //   logger.i('maxError: $maxError');
  // });

  test('test process no tempo', () {
    logger.i('test process tempo');

    ProcessTempo processTempo = ProcessTempo();

    bool lastInSignal = false;

    for (int sample = 0; sample < 4 * sampleRate; sample++) {
      int value = 0;

      processTempo.processNewTempo(value);
      logger.log(
        _logDetail,
        'sample $sample: ${value.toStringAsFixed(2).padLeft(9)}'
        ' $processTempo',
      );

      if (lastInSignal != processTempo.isSignal) {
        lastInSignal = processTempo.isSignal;
        logger.log(
          _logSummary,
          'sample ${sample.toString().padLeft(9)} = ${(sample / sampleRate).toStringAsFixed(3)}s:'
          ' ${value.toStringAsFixed(2).padLeft(8)}'
          ' $processTempo',
        );
      }
    }
    expect(processTempo.hertz, 0);
  });

  // testTempo(final int beatsPerMeasure) {
  //   double f = 180.0; //  tone pitch
  //   final ampMax = 1 << (audioConfiguration.bitDepth - 1);
  //   double toneFraction = 0.15;
  //
  //   ProcessTempo processTempo = ProcessTempo();
  //   processTempo.callback = () {
  //     logger.log(_logDetail, 'callback: bpm: ${processTempo.bestBpm}, tpm: ${processTempo.tapsPerMeasure}');
  //   };
  //
  //   int sample = 0;
  //
  //   processTempo.beatsPerMeasure = beatsPerMeasure;
  //   processTempo.verbose = true;
  //
  //   for (int currentBpm = 50; currentBpm <= 200; currentBpm += 50) {
  //     processTempo.expectedBpm = currentBpm; //  limit the range allowed
  //
  //     for (int tapsPerMeasure in [1, beatsPerMeasure != 3 ? 2 : beatsPerMeasure, beatsPerMeasure]) {
  //       logger.i('');
  //       logger.i('currentBpm: $currentBpm, $processTempo, beatsPerMeasure: $beatsPerMeasure');
  //
  //       bool lastInSignal = false;
  //       double periodS = 60 * beatsPerMeasure / (tapsPerMeasure * currentBpm);
  //       logger.i('currentBpm: $currentBpm, taps: $tapsPerMeasure => periodS $periodS = ${1 / periodS} hz');
  //       int sampleCycle = (sampleRate * periodS).toInt();
  //       int samplesOn = (sampleCycle * toneFraction).toInt();
  //
  //       int sampleEnd = sample + 28 * periodS.ceil() * sampleRate;
  //       print('sampleEnd: $sampleEnd = ${sampleEnd / sampleRate} s, sample: $sample');
  //       for (; sample < sampleEnd; sample++) {
  //         int value = 0;
  //         var amp = (sample % sampleCycle < samplesOn) ? ampMax : 0;
  //
  //         //  generate a pulse train every bpm
  //         value = (amp * sin(2 * pi * f * sample / sampleRate)).toInt();
  //
  //         processTempo.processNewTempo(value, epochUs: sample * Duration.microsecondsPerSecond / sampleRate);
  //         logger.log(
  //           _logDetail,
  //           'sample: $sample: ${value.toStringAsFixed(2).padLeft(9)}'
  //           ' $processTempo',
  //         );
  //
  //         if (lastInSignal != processTempo.isSignal) {
  //           lastInSignal = processTempo.isSignal;
  //           logger.log(
  //             _logSummary,
  //             'sample ${sample.toString().padLeft(9)} = ${(sample / sampleRate).toStringAsFixed(3)}s:'
  //             ' ${value.toStringAsFixed(2).padLeft(8)}'
  //             ' $processTempo',
  //           );
  //         }
  //       }
  //       expect(processTempo.bestBpm, currentBpm);
  //     }
  //   }
  // }

}
