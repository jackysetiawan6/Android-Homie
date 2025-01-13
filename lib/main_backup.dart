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
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blueAccent,
        ),
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
      appBar: AppBar(
        centerTitle: true,
        title: const Text("Home Dashboard"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SensorCard("Temperature", temperature, Icons.thermostat),
            const SizedBox(height: 16),
            SensorCard("Humidity", humidity, Icons.water_drop),
            const SizedBox(height: 16),
            SensorCard("Light Intensity", lightIntensity, Icons.light_mode),
            const SizedBox(height: 32),
            const Text(
              "LED Control",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    _setLedControlMode(1);
                    _publishLedControl(1);
                  },
                  child: const Text("Turn ON"),
                ),
                ElevatedButton(
                  onPressed: () {
                    _setLedControlMode(0);
                    _publishLedControl(0);
                  },
                  child: const Text("Turn OFF"),
                ),
                ElevatedButton(
                  onPressed: () {
                    _setLedControlMode(-1);
                    _publishLedControl(-1);
                  },
                  child: const Text("AUTO"),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                "LED State: $ledState (Mode: ${_ledControlModeText()})",
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
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

  const SensorCard(this.title, this.value, this.icon, {super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icon, size: 40, color: Colors.blue),
        title: Text(title, style: const TextStyle(fontSize: 18)),
        subtitle: Text(value, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}