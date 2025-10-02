import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:scidart/scidart.dart'; // for FFT
import 'package:scidart/numdart.dart'; // for FFT
import 'package:iirjdart/butterworth.dart'; // for Butterworth filter

class SignalSimulationPage extends StatefulWidget {
  const SignalSimulationPage({super.key});

  @override
  State<SignalSimulationPage> createState() => _SignalSimulationPageState();
}

class _SignalSimulationPageState extends State<SignalSimulationPage> {
  late FileStream _fileStream;
  StreamSubscription<List<List<double>>>? _subscription;

  final int _maxPoints = 100; // max points visible in the chart
  List<List<double>> _channelData = []; // buffer for all channels
  List<String> _channelNames = [];
  bool _isStreaming = false;

  // Display mode: 'signal', 'spectrum', 'bandpower'
  String _displayMode = 'signal';

  List<List<double>> _spectrumData = [];
  List<List<double>> _bandPowerData = [];

  String _filterType = 'None'; // 'None', 'Low Pass', 'High Pass', 'Band Pass'
  double _lowCut = 40.0;
  double _highCut = 1.0;
  List<List<double>> _filteredData = [];

  String _sleepStage = 'Awake';

  Timer? _stageTimer;

  double _samplingRate = 200.0; // Default sampling rate, changeable in UI

  @override
  void initState() {
    super.initState();
    _fileStream = FileStream(data: []);
  }

  void _startSleepStageTimer() {
    _stageTimer?.cancel();
    _stageTimer = Timer.periodic(const Duration(seconds: 5), (_) {//change to 30 seconds for real app
      setState(() {
        _sleepStage = _calculateSleepStage();
      });
    });
  }

  Future<void> _selectFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv', 'txt'],
  );

  if (result != null && result.files.single.path != null) {
    final path = result.files.single.path!;
    final file = File(path);
    final lines = await file.readAsLines();

    final data = lines.map((line) {
      // Skip first column (e.g., timestamps) before parsing to double
      final parts = line.split(',');
      return parts.skip(1).map((e) => double.tryParse(e) ?? 0.0).toList();
    }).toList();

    _fileStream = FileStream(
      data: data,
      chunkDuration: const Duration(milliseconds: 50), // 20 Hz streaming
    );
    _channelData = [];
    _channelNames = [];
    _subscription?.cancel();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Loaded file: ${result.files.single.name}')),
    );
  }
}


  void _startStreaming() {
    if (!_isStreaming) {
      _subscription = _fileStream.stream.listen((chunk) {
        if (chunk.isNotEmpty) {
          setState(() {
            if (_channelData.isEmpty) {
              _channelData = List.generate(chunk[0].length, (_) => []);
              _channelNames = List.generate(chunk[0].length, (i) => 'Channel ${i + 1}');
            }

            for (int ch = 0; ch < chunk[0].length; ch++) {
              _channelData[ch].addAll(chunk.map((s) => s[ch]));
              if (_channelData[ch].length > _maxPoints) {
                _channelData[ch] = _channelData[ch].sublist(
                    _channelData[ch].length - _maxPoints);
              }
            }
            _applyFilter();

            // Update spectrum or bandpower if needed
            if (_displayMode == 'spectrum') {
              // Log-transformed FFT for plotting
              _spectrumData = List.generate(
                _channelData.length,
                (ch) => _fileStream.computeFFT(channel: ch, windowSize: 128, logTransform: true),
              );
            } else if (_displayMode == 'bandpower') {
              // Normalized FFT for relative power
              _bandPowerData = List.generate(
                _channelData.length,
                (ch) => _computeBandPowers(channel: ch),
              );
            }
          });
        }
      });
      _fileStream.start();
      setState(() => _isStreaming = true);
      _startSleepStageTimer();
    }
  }


  void _stopStreaming() {
    if (_isStreaming) {
      _fileStream.stop();
      _subscription?.cancel();
      setState(() => _isStreaming = false);
      _stageTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _subscription?.cancel();
    _fileStream.stop();
    super.dispose();
  }

  Widget _buildChannelChart(int channelIndex) {
    if (_displayMode == 'bandpower') {
      // Average band powers across all channels
      if (_bandPowerData.isEmpty) return const SizedBox.shrink();

      final labels = ['delta', 'theta', 'alpha', 'sigma', 'beta'];
      final nChannels = _bandPowerData.length;

      final avgBandPowers = List.generate(labels.length, (i) {
        double sum = 0.0;
        for (var ch in _bandPowerData) {
          sum += ch[i];
        }
        return sum / nChannels;
      });

      return SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: 1.0, // normalized power
            barGroups: List.generate(avgBandPowers.length, (i) {
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: avgBandPowers[i],
                    color: Colors.green,
                    width: 18,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              );
            }),
            titlesData: FlTitlesData(
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 32),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (val, meta) {
                    if (val >= 0 && val < labels.length) {
                      return Text(labels[val.toInt()]);
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
            gridData: FlGridData(show: true),
            borderData: FlBorderData(show: false),
          ),
        ),
      );
    }

    // For signal or spectrum we keep using a line chart
    List<double> data = [];
    Color color = Colors.blue;

    if (_displayMode == 'signal') {
      data = _filteredData.isNotEmpty ? _filteredData[channelIndex] : [];
      color = Colors.blue;
    } else if (_displayMode == 'spectrum') {
      data = _spectrumData.isNotEmpty ? _spectrumData[channelIndex] : [];
      color = Colors.deepPurple;
    }

    final minY = data.isNotEmpty ? data.reduce((a, b) => a < b ? a : b) - 0.1 : 0;
    final maxY = data.isNotEmpty ? data.reduce((a, b) => a > b ? a : b) + 0.1 : 1;

    return SizedBox(
      height: 120,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(data.length, (i) => FlSpot(i.toDouble(), data[i])),
              isCurved: false,
              color: color,
              dotData: FlDotData(show: false),
              barWidth: 2,
            ),
          ],
          titlesData: FlTitlesData(show: false),
          gridData: FlGridData(show: true),
          borderData: FlBorderData(show: true),
          minY: minY.toDouble(),
          maxY: maxY.toDouble(),
        ),
      ),
    );
  }

  // Butterworth filter
  void _applyFilter() {
    if (_filterType == 'None') {
      _filteredData = List.from(_channelData);
      return;
    }
    final fs = _samplingRate; // Use selected sampling rate

    _filteredData = List.generate(_channelData.length, (ch) {
      final signal = _channelData[ch];
      List<double> filtered = [];
      if (_filterType == 'Low Pass') {
        final butter = Butterworth();
        butter.lowPass(4, fs, _lowCut);
        for (var v in signal) {
          filtered.add(butter.filter(v));
        }
      } else if (_filterType == 'High Pass') {
        final butter = Butterworth();
        butter.highPass(4, fs, _highCut);
        for (var v in signal) {
          filtered.add(butter.filter(v));
        }
      } else if (_filterType == 'Band Pass') {
        final butter = Butterworth();
        butter.bandPass(4, fs, _lowCut, _highCut);
        for (var v in signal) {
          filtered.add(butter.filter(v));
        }
      } else {
        filtered = List.from(signal);
      }
      return filtered;
    });
  }

  // Compute bandpowers for a given channel
  List<double> _computeBandPowers({int channel = 0}) {
    final spectrum = _fileStream.computeFFT(channel: channel, windowSize: 256);
    final binSize = _samplingRate / spectrum.length;

    double bandPower(double low, double high) {
      int lowBin = (low / binSize).floor();
      int highBin = (high / binSize).ceil();
      return spectrum.sublist(lowBin, highBin).fold(0.0, (a, b) => a + b);
    }

    final delta = bandPower(0.5, 4);
    final theta = bandPower(4, 8);
    final alpha = bandPower(8, 12);
    final sigma = bandPower(12, 15);
    final beta = bandPower(15, 30);

    final total = delta + theta + alpha + sigma + beta + 1e-6;
    return [delta / total, theta / total, alpha / total, sigma / total, beta / total];
  }

  String _calculateSleepStage() {
    if (_filteredData.isEmpty || _filteredData[0].isEmpty) return 'Awake';

    // Compute band powers for all channels
    final bandPowers = List.generate(
      _channelData.length,
      (ch) => _computeBandPowers(channel: ch),
    );

    // Average relative band powers across channels
    double avgDelta = 0.0;
    double avgTheta = 0.0;
    double avgAlpha = 0.0;
    double avgSigma = 0.0;
    double avgBeta = 0.0;

    for (var bp in bandPowers) {
      avgDelta += bp[0];
      avgTheta += bp[1];
      avgAlpha += bp[2];
      avgSigma += bp[3];
      avgBeta += bp[4];
    }

    final nChannels = bandPowers.length;
    avgDelta /= nChannels;
    avgTheta /= nChannels;
    avgAlpha /= nChannels;
    avgSigma /= nChannels;
    avgBeta /= nChannels;

    // Sleep staging thresholds (heuristic)
    if (avgAlpha > 0.3 && avgBeta > 0.2) return 'Awake1';
    if (avgTheta > 0.4 && avgAlpha < 0.2) return 'N1';
    if (avgSigma > 0.1 && avgTheta > 0.3) return 'N2';
    if (avgDelta > 0.5) return 'N3';
    if (avgBeta > 0.3 && avgDelta < 0.2) return 'REM';

    return 'Awake2'; // fallback
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signal Simulation'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(0.0),
                child: Column(
                  children: [
                    ElevatedButton(onPressed: _selectFile, child: const Text('Select EEG File')),
                    const SizedBox(height: 6),
                    ElevatedButton(onPressed: _startStreaming, child: const Text('Start Streaming')),
                    const SizedBox(height: 6),
                    ElevatedButton(onPressed: _stopStreaming, child: const Text('Stop Streaming')),
                    const SizedBox(height: 6),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          if (_displayMode == 'signal') {
                            // Show log-transformed FFT spectrum
                            _spectrumData = List.generate(
                              _channelData.length,
                              (ch) => _fileStream.computeFFT(channel: ch, windowSize: 128, logTransform: true),
                            );
                            _displayMode = 'spectrum';
                          } else if (_displayMode == 'spectrum') {
                            // Show bandpowers (normalized)
                            _bandPowerData = List.generate(
                              _channelData.length,
                              (ch) => _computeBandPowers(channel: ch),
                            );
                            _displayMode = 'bandpower';
                          } else {
                            _displayMode = 'signal';
                          }
                        });
                      },
                      child: Text(
                        _displayMode == 'signal'
                            ? 'Show FFT Spectrum'
                            : _displayMode == 'spectrum'
                                ? 'Show BandPower'
                                : 'Show Signal',
                      ),
                    ),

                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Sampling Rate:'),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: TextEditingController(text: _samplingRate.toStringAsFixed(1)),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            onSubmitted: (val) {
                              setState(() {
                                final parsed = double.tryParse(val);
                                if (parsed != null && parsed > 0) {
                                  _samplingRate = parsed;
                                  _applyFilter();
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Hz'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Filter:'),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: _filterType,
                          items: ['None', 'Low Pass', 'High Pass', 'Band Pass']
                              .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              _filterType = val!;
                              _applyFilter();
                            });
                          },
                        ),
                        if (_filterType == 'Low Pass' || _filterType == 'Band Pass') ...[
                          const SizedBox(width: 8),
                          const Text('Low:'),
                          SizedBox(
                            width: 60,
                            child: TextField(
                              controller: TextEditingController(text: _lowCut.toStringAsFixed(1)),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              onSubmitted: (val) {
                                setState(() {
                                  _lowCut = double.tryParse(val) ?? _lowCut;
                                  _applyFilter();
                                });
                              },
                            ),
                          ),
                        ],
                        if (_filterType == 'High Pass' || _filterType == 'Band Pass') ...[
                          const SizedBox(width: 8),
                          const Text('High:'),
                          SizedBox(
                            width: 60,
                            child: TextField(
                              controller: TextEditingController(text: _highCut.toStringAsFixed(1)),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              onSubmitted: (val) {
                                setState(() {
                                  _highCut = double.tryParse(val) ?? _highCut;
                                  _applyFilter();
                                });
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Text(
                              _sleepStage,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Display charts
                    if (_displayMode == 'bandpower')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: _buildChannelChart(0), // index ignored, averaged
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _channelData.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: _buildChannelChart(index),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

// ---------------------------------------------------
// FileStream class that generates a broadcast stream
// ---------------------------------------------------
class FileStream {
  final List<List<double>> data;
  final Duration chunkDuration;
  final StreamController<List<List<double>>> _controller = StreamController.broadcast();

  Stream<List<List<double>>> get stream => _controller.stream;
  Timer? _timer;
  int _index = 0;

  FileStream({required this.data, this.chunkDuration = const Duration(milliseconds: 50)});

  void start() {
    if (_timer != null && _timer!.isActive) return;

    _timer = Timer.periodic(chunkDuration, (_) {
      if (_index >= data.length) {
        _timer?.cancel();
        return;
      }
      _controller.add([data[_index]]);
      _index++;
    });
  }

  void stop() {
    _timer?.cancel();
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }

  /// Computes the FFT of a given channel's data up to the current index.
  /// Returns the magnitude spectrum normalized so that total power = 1.
  /// Optionally returns log-transformed magnitude for plotting.
  List<double> computeFFT({int channel = 0, int windowSize = 128, bool logTransform = false}) {
    // Determine window start
    final int start = (_index - windowSize).clamp(0, data.length - 1);

    // Extract windowed signal
    final List<double> window = [
      for (int i = start; i < _index; i++) data[i][channel]
    ];

    // Pad with zeros if needed
    if (window.length < windowSize) {
      window.insertAll(0, List.filled(windowSize - window.length, 0.0));
    }

    // Apply Hanning window to reduce spectral leakage
    final List<double> hannWindow = [
      for (int n = 0; n < windowSize; n++)
        window[n] * 0.5 * (1 - cos(2 * pi * n / (windowSize - 1)))
    ];

    // Convert to ArrayComplex for FFT
    final ArrayComplex input = ArrayComplex([
      for (var v in hannWindow) Complex(real: v, imaginary: 0.0)
    ]);

    final ArrayComplex fftResult = fft(input);

    // Compute magnitude spectrum
    final List<double> mag = arrayComplexAbs(fftResult).toList();

    // Normalize total power to 1
    final double totalPower = mag.fold(0.0, (a, b) => a + b);
    List<double> normalized = totalPower > 0
        ? mag.map((v) => v / totalPower).toList()
        : List.filled(mag.length, 0.0);

    if (logTransform) {
      // Convert to dB scale for plotting: 10*log10(magnitude)
      normalized = normalized.map((v) => 10 * log(v + 1e-12) / ln10).toList();
    }

    return normalized;
  }
}
