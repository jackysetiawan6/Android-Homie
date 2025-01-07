import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const HomieApp());
}

class HomieApp extends StatelessWidget {
  const HomieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Homie Dashboard',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
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
  String temperature = "Gathering information...";
  String humidity = "Gathering information...";
  String lightIntensity = "Gathering information...";
  String ledState = "Unknown";
  int ledControlMode = -1;
  bool isDark = false;

  late MqttServerClient client;
  final String mqttEndpoint = "a1kwmoq0xfo7wp-ats.iot.us-east-1.amazonaws.com";
  final String mqttTopic = "sensor_group_03";
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
    const Uuid uuid = Uuid();
    final String clientId = uuid.v4();
    client = MqttServerClient(mqttEndpoint, clientId)
      ..port = 8883
      ..secure = true
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..logging(on: true);

    final context = await _loadSecurityContext();
    client.securityContext = context;
    client.setProtocolV311();

    client.onConnected = _onConnected;
    client.onDisconnected = _onDisconnected;
    client.onSubscribed = _onSubscribed;

    try {
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

      context.setClientAuthoritiesBytes(rootCA.buffer.asUint8List());
      context.useCertificateChainBytes(deviceCert.buffer.asUint8List());
      context.usePrivateKeyBytes(privateKey.buffer.asUint8List());
    } catch (e) {
      debugPrint("Failed to load security context: $e");
    }

    return context;
  }

  void _onConnected() {
    debugPrint("Connected to MQTT broker");
    reconnectTimer?.cancel();
    client.subscribe(mqttTopic, MqttQos.atMostOnce);
  }

  void _onDisconnected() {
    debugPrint("Disconnected from MQTT broker");
    if (reconnectTimer == null || !reconnectTimer!.isActive) {
      reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        debugPrint("Attempting to reconnect...");
        _initializeMQTTClient();
      });
    }
  }

  void _onSubscribed(String topic) {
    debugPrint("Subscribed to topic: $topic");
    client.updates?.listen((messages) {
      final recMessage = messages[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(recMessage.payload.message);

      try {
        final jsonData = json.decode(payload);
        _updateSensorValues(jsonData);
      } catch (e) {
        debugPrint("Failed to parse message: $e");
        _resetSensorValues();
      }
    });
  }

  void _updateSensorValues(Map<String, dynamic> jsonData) {
    setState(() {
      temperature = jsonData['Temperature'] != null ? "${jsonData['Temperature']}°C" : "No data found";
      humidity = jsonData['Humidity'] != null ? "${jsonData['Humidity']}%" : "No data found";
      lightIntensity = jsonData['Light'] != null ? "${jsonData['Light']} Lux" : "No data found";
      ledState = jsonData['LED_State'] == 1 ? "ON" : "OFF";
      isDark = jsonData['Light'] < 800;
    });
  }

  void _resetSensorValues() {
    setState(() {
      temperature = "No data found";
      humidity = "No data found";
      lightIntensity = "No data found";
      ledState = "Unknown";
    });
  }

  void _publishLedControl(int mode) {
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      final payload = json.encode({"LED_Override": mode});
      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);

      client.publishMessage(mqttTopic, MqttQos.atLeastOnce, builder.payload!);
      debugPrint("Published LED control mode: $mode");
    } else {
      debugPrint("Unable to publish. MQTT client is not connected.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo.shade50,
      body: SafeArea(
        child: Container(
          margin: const EdgeInsets.only(top: 18, left: 24, right: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Homie IoT Dashboard",
                    style: TextStyle(
                      fontSize: 18,
                      fontFamily: 'Overpass',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(Icons.light_mode, color: Colors.indigo, size: 20),
                ],
              ),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SensorCard('Temperature', temperature, Icons.thermostat_outlined, null),
                        SensorCard('Humidity', humidity, Icons.water_drop_outlined, null),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SensorCard("Light Intensity", lightIntensity, Icons.light_mode_outlined, null),
                        SensorCard("LED", ledState, ledState == "ON" ? Icons.flash_on_outlined : Icons.flashlight_off_outlined, null),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'HISTORICAL GRAPH',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setLedControlMode(int mode) {
    setState(() => ledControlMode = mode);
  }

  String _ledControlModeText() {
    return ledControlMode == 1
        ? "Manual ON"
        : ledControlMode == 0
        ? "Manual OFF"
        : "AUTO";
  }
}

class SensorCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color = Colors.white;
  final Color fontColor = Colors.grey;
  final VoidCallback? onTap;

  const SensorCard(this.title, this.value, this.icon, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: fontColor)),
          ],
        ),
      ),
    );
  }
}