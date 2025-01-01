import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:async';
import 'dart:io';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF0A0E21),
      primaryColor: const Color(0xFF1D1F33),
      cardColor: const Color(0xFF1D1F33),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0A0E21),
        elevation: 0,
        titleTextStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3A3E55),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: Colors.white),
      ),
    ),
    home: const HomieScreen(),
  ));
}

class HomieScreen extends StatefulWidget {
  const HomieScreen({super.key});

  @override
  State<HomieScreen> createState() => _HomieScreenState();
}

class _HomieScreenState extends State<HomieScreen> {
  double temperature = 0.0;
  double humidity = 0.0;
  double lightIntensity = 0.0;
  String ledStatus = "OFF";

  late MqttServerClient client;
  final String mqttEndpoint = "a1kwmoq0xfo7wp-ats.iot.us-east-1.amazonaws.com";
  final String mqttTopic = "sensor_group_03";

  Timer? reconnectTimer;

  Future<void> connectAWSIoT() async {
    client = MqttServerClient(mqttEndpoint, '');
    client.port = 8883;
    client.secure = true;
    client.logging(on: true);

    final context = SecurityContext.defaultContext;
    context.setClientAuthorities('assets/AmazonRootCA1.pem');
    context.useCertificateChain(
        'assets/2a824b30019e3d44560d0ca4212f8aefcbec4dd0161ffbb4d3f931329d2f8856-certificate.pem.crt');
    context.usePrivateKey(
        'assets/2a824b30019e3d44560d0ca4212f8aefcbec4dd0161ffbb4d3f931329d2f8856-private.pem.key');

    client.securityContext = context;
    client.setProtocolV311();

    client.onConnected = onConnected;
    client.onDisconnected = onDisconnected;
    client.onSubscribed = onSubscribed;

    try {
      await client.connect();
    } catch (e) {
      client.disconnect();
    }
  }

  void onConnected() {
    if (reconnectTimer != null) {
      reconnectTimer!.cancel();
    }
    client.subscribe(mqttTopic, MqttQos.atMostOnce);
  }

  void onDisconnected() {
    if (reconnectTimer == null || !reconnectTimer!.isActive) {
      reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        debugPrint("Attempting to reconnect...");
        connectAWSIoT();
      });
    }
  }

  void onSubscribed(String topic) {
    client.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? messages) {
      final recMessage = messages![0].payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(recMessage.payload.message);

      final sensorData = parseSensorData(payload);

      setState(() {
        temperature = sensorData['Temperature'];
        humidity = sensorData['Humidity'];
        lightIntensity = sensorData['light'];
      });

      if (ledStatus == "AUTO") {
        if (temperature < 20.0 || lightIntensity < 200.0) {
          ledStatus = "ON";
        } else {
          ledStatus = "OFF";
        }
      }
    });
  }

  Map<String, dynamic> parseSensorData(String payload) {
    try {
      return Map<String, dynamic>.from(Uri.parse(payload) as Map);
    } catch (e) {
      return {"temperature": 0.0, "humidity": 0.0, "lightIntensity": 0.0};
    }
  }

  @override
  void initState() {
    super.initState();
    connectAWSIoT();
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    client.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          "Homie Dashboard",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildSensorCard("Temperature", "$temperature °C",
                Icons.thermostat_outlined, Colors.blueAccent),
            const SizedBox(height: 16),
            _buildSensorCard(
                "Humidity", "$humidity %", Icons.water_drop, Colors.lightBlue),
            const SizedBox(height: 16),
            _buildSensorCard("Light Intensity", "$lightIntensity Lux",
                Icons.lightbulb, Colors.yellowAccent),
            const SizedBox(height: 32),
            const Text(
              "LED Control",
              style: TextStyle(fontSize: 22, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => setState(() => ledStatus = "ON"),
                  child: const Text("Turn ON"),
                ),
                ElevatedButton(
                  onPressed: () => setState(() => ledStatus = "OFF"),
                  child: const Text("Turn OFF"),
                ),
                ElevatedButton(
                  onPressed: () => setState(() => ledStatus = "AUTO"),
                  child: const Text("AUTO"),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                "LED Status: $ledStatus",
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard(
      String title, String value, IconData icon, Color iconColor) {
    return Card(
      color: const Color(0xFF1D1F33),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icon, size: 40, color: iconColor),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, color: Colors.white),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(fontSize: 16, color: Colors.white54),
        ),
      ),
    );
  }
}
