import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const HomieApp());
}

class HomieApp extends StatelessWidget {
  const HomieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Homie Monitoring System',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const HomieScreen(),
    );
  }
}

class HomieScreen extends StatefulWidget {
  const HomieScreen({super.key});

  @override
  State<HomieScreen> createState() => _HomieScreenState();
}

class _HomieScreenState extends State<HomieScreen> {
  final String mqttEndpoint = "a1kwmoq0xfo7wp-ats.iot.us-east-1.amazonaws.com";
  final String mqttTopic = "sensor_group_03";
  late MqttServerClient client;
  late int counter = 0;

  String temperature = "Gathering...";
  String humidity = "Gathering...";
  String lightIntensity = "Gathering...";
  String ledState = "Unknown";

  final List<double> tempData = [];
  final List<double> humData = [];
  final List<double> lightData = [];

  Timer? reconnectTimer;

  @override
  void initState() {
    super.initState();
    _initializeMQTTClient();
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    client.disconnect();
    super.dispose();
  }

  Future<void> _initializeMQTTClient() async {
    final String clientId = const Uuid().v4();
    client = MqttServerClient(mqttEndpoint, clientId)
      ..port = 8883
      ..secure = true
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..logging(on: true)
      ..onConnected = _onConnected
      ..onDisconnected = _onDisconnected;

    client.setProtocolV311();
    client.onSubscribed = (topic) => debugPrint("Subscribed to $topic");

    try {
      client.securityContext = await _loadSecurityContext();
      await client.connect();
    } catch (e) {
      debugPrint("MQTT connection failed: $e");
      client.disconnect();
    }
  }

  Future<SecurityContext> _loadSecurityContext() async {
    final context = SecurityContext.defaultContext;
    try {
      final rootCA = await rootBundle.load('assets/RootCA.pem');
      final deviceCert = await rootBundle.load('assets/DeviceCert.crt');
      final privateKey = await rootBundle.load('assets/Private.key');

      context
        ..setClientAuthoritiesBytes(rootCA.buffer.asUint8List())
        ..useCertificateChainBytes(deviceCert.buffer.asUint8List())
        ..usePrivateKeyBytes(privateKey.buffer.asUint8List());
    } catch (e) {
      debugPrint("Failed to load security context: $e");
    }
    return context;
  }

  void _onConnected() {
    debugPrint("Connected to MQTT broker");
    reconnectTimer?.cancel();
    client.subscribe(mqttTopic, MqttQos.atMostOnce);
    client.updates?.listen(_handleMessages);
  }

  void _onDisconnected() {
    debugPrint("Disconnected from MQTT broker");
    reconnectTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      debugPrint("Attempting to reconnect...");
      _initializeMQTTClient();
    });
  }

  void _handleMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    final message = messages.first.payload as MqttPublishMessage;
    final payload =
    MqttPublishPayload.bytesToStringAsString(message.payload.message);
    try {
      final jsonData = json.decode(payload) as Map<String, dynamic>;
      _updateSensorValues(jsonData);
      _updateGraphValues(jsonData);
    } catch (e) {
      debugPrint("Failed to parse message: $e");
      _resetSensorValues();
    }
  }

  void _updateSensorValues(Map<String, dynamic> jsonData) {
    setState(() {
      temperature = jsonData['Temperature'] != null
          ? "${jsonData['Temperature']} °C"
          : "Gathering...";
      humidity = jsonData['Humidity'] != null
          ? "${jsonData['Humidity']} %"
          : "Gathering...";
      lightIntensity = jsonData['Light'] != null
          ? "${jsonData['Light']} Lux"
          : "Gathering...";
      ledState = jsonData['LED_State'] == 1 ? "ON" : "OFF";
    });
  }

  void _updateGraphValues(Map<String, dynamic> jsonData) {
    counter = (counter + 1) % 6;
    if (counter == 0) {
      _addToGraph(tempData, _tryParseSensorValue(temperature));
      _addToGraph(humData, _tryParseSensorValue(humidity));
      _addToGraph(lightData, _tryParseSensorValue(lightIntensity));
    }
  }

  void _addToGraph(List<double> data, double? value) {
    if (value != null) {
      data.add(double.parse(value.toStringAsFixed(1)));
      if (data.length > 12) data.removeAt(0);
    }
  }

  double? _tryParseSensorValue(String value) {
    try {
      double newVal = double.parse(value.split(' ')[0]);
      newVal = newVal > 100 ? newVal / 1024 * 100 : newVal;
      return newVal;
    } catch (_) {
      return null;
    }
  }

  void _resetSensorValues() {
    setState(() {
      temperature = humidity = lightIntensity = ledState = "Gathering...";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo.shade50,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 32),
              _buildSensorCards(),
              const SizedBox(height: 32),
              const Text(
                'HISTORICAL GRAPH',
                style: TextStyle(
                  fontFamily: 'Overpass',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.only(top: 16, left: 24, right: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    LegendItem(color: Colors.redAccent, label: "Temperature"),
                    LegendItem(color: Colors.indigoAccent, label: "Humidity"),
                    LegendItem(color: Colors.orangeAccent, label: "Light"),
                  ],
                ),
              ),
              Expanded(child: _buildGraphContainer()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Homie Monitoring System",
          style: TextStyle(
            fontSize: 18,
            fontFamily: 'Overpass',
            fontWeight: FontWeight.bold,
          ),
        ),
        Row(
          children: [
            Icon(Icons.light_mode_outlined, color: Colors.indigoAccent, size: 20),
            SizedBox(width: 8),
            Icon(Icons.info_outline, color: Colors.indigoAccent, size: 20),
          ],
        ),
      ],
    );
  }

  Widget _buildSensorCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: SensorCard(title: 'Temperature', value: temperature, iconData: Icons.hot_tub_outlined)),
            const SizedBox(width: 16),
            Expanded(child: SensorCard(title: 'Humidity', value: humidity, iconData: Icons.water_drop_outlined)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: SensorCard(title: 'Light Intensity', value: lightIntensity, iconData: Icons.light_mode_outlined)),
            const SizedBox(width: 16),
            Expanded(child: SensorCard(title: 'LED', value: ledState, iconData: Icons.flashlight_off_outlined)),
          ],
        ),
      ],
    );
  }

  Widget _buildGraphContainer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 25, 25, 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: tempData.isEmpty
          ? const Center(
        child: Text(
          "Gathering...",
          style: TextStyle(
            fontFamily: 'Overpass',
            color: Colors.indigo,
            fontWeight: FontWeight.bold,
          ),
        ),
      )
          : CustomChart(tempData: tempData, humData: humData, lightData: lightData),
    );
  }
}

class SensorCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData iconData;

  const SensorCard({required this.title, required this.value, required this.iconData, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(iconData, color: Colors.indigo, size: 32),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Overpass', color: Colors.black),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontFamily: 'Overpass', color: Colors.indigo),
          ),
        ],
      ),
    );
  }
}

class CustomChart extends StatelessWidget {
  final List<double> tempData;
  final List<double> humData;
  final List<double> lightData;

  const CustomChart({
    required this.tempData,
    required this.humData,
    required this.lightData,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 22, interval: 1,
              getTitlesWidget: (value, meta) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(0, 5, 0, 0),
                  child: Text((value.toInt() + 1).toString(), style: const TextStyle(fontSize: 12, fontFamily: 'Overpass')
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 35, interval: 10,
              getTitlesWidget: (value, meta) {
                if (value % 10 == 0 && value >= 0 && value <= 100) {
                  return Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                    child: Text(
                      value.toInt().toString(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, fontFamily: 'Overpass'),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: 100,
        lineBarsData: [
          _buildLineBarData(tempData, Colors.redAccent),
          _buildLineBarData(humData, Colors.indigoAccent),
          _buildLineBarData(lightData, Colors.orangeAccent),
        ],
      ),
    );
  }

  LineChartBarData _buildLineBarData(List<double> data, Color color) {
    return LineChartBarData(
        spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
        isCurved: true,
        color: color,
        barWidth: 3,
        isStrokeCapRound: true,
        show: true
    );
  }
}

class LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const LegendItem({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontFamily: 'Overpass'),
        ),
      ],
    );
  }
}