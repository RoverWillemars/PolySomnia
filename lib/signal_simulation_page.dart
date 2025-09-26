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
  bool _showSpectrum = false;
  List<List<double>> _spectrumData = [];

  String _filterType = 'None'; // 'None', 'Low Pass', 'High Pass', 'Band Pass'
  double _lowCut = 1.0;
  double _highCut = 40.0;
  List<List<double>> _filteredData = [];

  @override
  void initState() {
    super.initState();
    // initialize with a default dummy stream (empty)
    _fileStream = FileStream(data: []);
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
        // parse CSV lines into List<List<double>>, if its 0, it means it couldnt parse
        return line.split(',').map((e) => double.tryParse(e) ?? 0.0).toList(); 
      }).toList(); 

      _fileStream = FileStream(data: data, chunkDuration: const Duration(milliseconds: 50)); //20Hz streaming; 
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

            // Recompute spectrum if in spectrum mode
            if (_showSpectrum) {
              _spectrumData = List.generate(
                _channelData.length,
                (ch) => _fileStream.computeFFT(channel: ch, windowSize: 128),
              );
            }
          });
        }
      });
      _fileStream.start();
      setState(() => _isStreaming = true);
    }
  }

  void _stopStreaming() {
    if (_isStreaming) {
      _fileStream.stop();
      _subscription?.cancel();
      setState(() => _isStreaming = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _fileStream.stop();
    super.dispose();
  }

  Widget _buildChannelChart(int channelIndex) {
    final data = _showSpectrum
        ? (_spectrumData.isNotEmpty ? _spectrumData[channelIndex] : [])
        : (_filteredData.isNotEmpty ? _filteredData[channelIndex] : []);
    final minY = data.isNotEmpty ? data.cast<double>().reduce((a, b) => a < b ? a : b) - 5 : 0;
    final maxY = data.isNotEmpty ? data.cast<double>().reduce((a, b) => a > b ? a : b) + 5 : 10;
    return SizedBox(
      height: 120,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(data.length, (i) => FlSpot(i.toDouble(), data[i] as double)),
              isCurved: false,
              color: _showSpectrum ? Colors.deepPurple : Colors.blue,
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
    final fs = 20.0; // Sampling rate (Hz), adjust if needed

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signal Simulation'), centerTitle: true),
      body: Padding(
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
                  if (!_showSpectrum) {
                    _spectrumData = List.generate(
                      _channelData.length,
                      (ch) => _fileStream.computeFFT(channel: ch, windowSize: 128),
                    );
                    _showSpectrum = true;
                  } else {
                    _showSpectrum = false;
                  }
                });
              },
              child: Text(_showSpectrum ? 'Show Signal' : 'Show FFT Spectrum'),
            ),
            const SizedBox(height: 12),
            Row(
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
            const SizedBox(height: 6),
            Expanded(
              child: ListView.builder(
                itemCount: _channelData.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildChannelChart(index),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
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
  /// Returns the magnitude spectrum.
  List<double> computeFFT({int channel = 0, int windowSize = 128}) {
    final int start = (_index - windowSize).clamp(0, data.length - 1);
    final List<double> window = [
      for (int i = start; i < _index; i++) data[i][channel]
    ];
    if (window.length < windowSize) {
      window.insertAll(0, List.filled(windowSize - window.length, 0.0));
    }
    final Array real = Array(window);
    final ArrayComplex input = ArrayComplex([
      for (var v in real) Complex(real: v, imaginary: 0.0)
    ]);
    final ArrayComplex fftResult = fft(input);
    return arrayComplexAbs(fftResult).toList();
  }
}



