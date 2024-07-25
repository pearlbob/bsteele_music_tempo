import 'dart:collection';
import 'dart:math';

import 'package:bsteele_music_lib/songs/music_constants.dart';
import 'package:bsteele_music_tempo/app_logger.dart';
import 'package:bsteele_music_tempo/audio_configuration.dart';
import 'package:bsteele_music_tempo/process_tempo.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const Level _logDetail = Level.debug;
const Level _logSummary = Level.debug;

int _lastBestBpm = -1;
int _currentBpm = -1;

void main() {
  Logger.level = Level.info;

  test('test process tempo filter', () {
    logger.i('test process tempo filter');

    ProcessTempo processTempo = ProcessTempo();

    processTempo.callback = () {
      if (_lastBestBpm != processTempo.bestBpm) {
        logger.i('   callback:  bpm: ${processTempo.bestBpm.toString().padLeft(3)}'
            ' at $_currentBpm bpm');
        _lastBestBpm = processTempo.bestBpm;
      }
    };

    //  notice that the same process temp measures all of them.
    //  so the initial measure can be quite wrong

    double f = 180.0; //  tone pitch
    int sample = 0;

    int maxError = 0;
    for (int beatsPerMeasure in [
      //2, 3, 4,
      6
    ]) {
      //  compute the possible logical beats per bar
      SplayTreeSet<int> beatsPerBarSet = SplayTreeSet();
      for (int divisor in [
        //1,
        //2,
        4
      ]) {
        beatsPerBarSet.add(beatsPerMeasure ~/ divisor);
      }
      beatsPerBarSet.remove(0);

      for (int beatsPerBar in beatsPerBarSet) {
        for (_currentBpm = MusicConstants.minBpm; _currentBpm < 180; _currentBpm += 5) {
          double periodS = 60 / _currentBpm;
          double toneFraction = 0.15;
          int sampleCycle = (sampleRate * periodS).toInt();
          int samplesOn = (sampleCycle * toneFraction).toInt();
          sampleCycle *= beatsPerBar;

          processTempo.expectedBpm = _currentBpm;
          processTempo.beatsPerMeasure = beatsPerMeasure;

          int offset = 0;
          var amp = 0;
          const ampMax = 1 << (bitDepth - 1);
          const ampMin = 1;
          bool lastInSignal = false;

          for (int signalMax in [ampMax ~/ 2]) {
            for (int s = 0; s < 20 * sampleCycle; s++) {
              sample++;
              int value = 0;
              if (sample > offset) {
                var index = sample - offset;

                //  generate a pulse train every bpm
                amp = (index % sampleCycle < samplesOn) ? signalMax : ampMin;
                // if ( amp != lastAmp){
                //   int delta = sample - lastAmpSample;
                //   logger.i('sample $sample: amp: ${amp.toString().padLeft(5)}'
                //       ', +samples: ${(delta/sampleRate).toStringAsFixed(3)} s');
                //   lastAmp = amp;
                //   lastAmpSample = sample;
                // }
                value = (amp * sin(2 * pi * f * index / sampleRate)).toInt();
              }

              processTempo.processNewTempo(value, epochUs: sample * Duration.microsecondsPerSecond ~/ sampleRate);
              logger.log(
                  _logDetail,
                  'sample $sample: ${value.toStringAsFixed(2).padLeft(9)}'
                  ' $processTempo');

              if (lastInSignal != processTempo.isSignal) {
                lastInSignal = processTempo.isSignal;
                logger.log(
                    _logSummary,
                    'sample ${sample.toString().padLeft(9)} = ${(sample / sampleRate).toStringAsFixed(3)}s:'
                    ' ${value.toStringAsFixed(2).padLeft(8)}'
                    ' $processTempo');
              }
            }

            logger.i(
                'perBar: $beatsPerBar, beats: $beatsPerMeasure, bestBpm: ${processTempo.bestBpm}, signalMax: $signalMax');
            int error = processTempo.bestBpm - _currentBpm;
            error = error.abs();
            logger.i('   error: $error');
            maxError = max(maxError, error);
            expect(error <= 1, isTrue);

            //  clear the prior taps for the new tempo
            for (int s = 0; s < 20 * sampleCycle; s++) {
              sample++;
              processTempo.processNewTempo(0, epochUs: sample * Duration.microsecondsPerSecond ~/ sampleRate);
            }
          }

          // logger.i('');
        }
      }
    }

    logger.i('maxError: $maxError');
  });
}
