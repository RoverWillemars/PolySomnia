import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';

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

  @override
  void initState() {
    super.initState();
    // initialize with a default dummy stream (empty)
    _fileStream = FileStream(data: []);
  }

  Future<void> _selectFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'], //csv file is best currently. downloaded from https://physionet.org/content/auditory-eeg/1.0.0/Filtered_Data/#files-panel
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final file = File(path);
      final lines = await file.readAsLines();
      final data = lines.map((line) {
        return line.split(',').map((e) => double.tryParse(e) ?? 0.0).toList();
      }).toList();

      _fileStream = FileStream(data: data, chunkDuration: const Duration(milliseconds: 50));
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

  // channel 1 doesnt work, maybe cause of the csv header?
  Widget _buildChannelChart(int channelIndex) {
    final data = _channelData[channelIndex];
    return SizedBox(
      height: 120,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(data.length, (i) => FlSpot(i.toDouble(), data[i])),
              isCurved: false,
              color: Colors.blue,
              dotData: FlDotData(show: false),
              barWidth: 2,
            ),
          ],
          titlesData: FlTitlesData(show: false),
          gridData: FlGridData(show: true),
          borderData: FlBorderData(show: true),
          minY: data.isNotEmpty ? data.reduce((a, b) => a < b ? a : b) - 5 : 0,
          maxY: data.isNotEmpty ? data.reduce((a, b) => a > b ? a : b) + 5 : 10,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signal Simulation'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            ElevatedButton(onPressed: _selectFile, child: const Text('Select EEG File')),
            const SizedBox(height: 6),
            ElevatedButton(onPressed: _startStreaming, child: const Text('Start Streaming')),
            const SizedBox(height: 6),
            ElevatedButton(onPressed: _stopStreaming, child: const Text('Stop Streaming')),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _channelData.length,
                itemBuilder: (context, index) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_channelNames[index], style: const TextStyle(fontWeight: FontWeight.bold)),
                      _buildChannelChart(index),
                      const SizedBox(height: 12),
                    ],
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
}
