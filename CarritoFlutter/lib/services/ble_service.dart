import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';

class BLEService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  final Logger _logger = Logger();
  bool isConnected = false;

  // StreamController para datos recibidos
  final StreamController<Map<String, double>> _dataController =
      StreamController.broadcast();

  Stream<Map<String, double>> get dataStream => _dataController.stream;

  // Buffer para acumular datos
  final List<int> _buffer = [];

  // Subscription para las notificaciones
  StreamSubscription<List<int>>? _notificationSubscription;

  Future<void> scanForDevices({
    required Function(String deviceName) onDeviceFound,
    required Function(bool found) onScanComplete,
  }) async {
    bool deviceFound = false;

    // Inicia el escaneo
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    // Escucha los resultados del escaneo
    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        _logger.i('Dispositivo encontrado: ${r.device.platformName}');

        // Si el nombre del dispositivo coincide con el módulo Bluetooth
        if (r.device.name == 'HMSoft' || r.device.platformName == 'BT05') {
          await FlutterBluePlus.stopScan();
          await _connectToDevice(r.device);
          onDeviceFound(r.device.platformName);
          deviceFound = true;
          break;
        }
      }
    });

    // Escucha el estado de escaneo
    FlutterBluePlus.isScanning.listen((isScanning) {
      if (!isScanning && !deviceFound) {
        onScanComplete(false);
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);
      _device = device;
      isConnected = true;
      _logger.i('Conectado a ${device.platformName}');
      await _discoverServices();
    } catch (e) {
      _logger.e('Error al conectar con el dispositivo: $e');
    }
  }

  Future<void> _discoverServices() async {
    if (_device == null) return;

    List<BluetoothService> services = await _device!.discoverServices();
    for (var service in services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.properties.write &&
            (characteristic.properties.notify ||
                characteristic.properties.indicate)) {
          _characteristic = characteristic;

          // No iniciar las notificaciones aquí. Solo almacenar la característica.
          _logger.i('Característica encontrada y lista para usarse.');
          break;
        }
      }
      if (_characteristic != null) break;
    }
    if (_characteristic == null) {
      _logger.w('No se encontró una característica adecuada.');
    }
  }

  void startListening() async {
    if (_characteristic != null) {
      try {
        await _characteristic!.setNotifyValue(true);
        _notificationSubscription = _characteristic!.value.listen(
          (value) {
            _processReceivedData(value);
          },
          onError: (error) {
            _logger.e('Error en la suscripción de notificaciones: $error');
          },
          onDone: () {
            _logger.i('Suscripción de notificaciones cerrada.');
          },
        );
        _logger.i('Inicio de recepción de datos.');
      } catch (e) {
        _logger.e('Error al iniciar la recepción de datos: $e');
      }
    } else {
      _logger.w(
          'No se puede iniciar la recepción: característica no inicializada.');
    }
  }

  void stopListening() async {
    if (_notificationSubscription != null) {
      try {
        await _characteristic!.setNotifyValue(false);
        await _notificationSubscription!.cancel();
        _notificationSubscription = null;
        _logger.i('Recepción de datos detenida.');
      } catch (e) {
        _logger.e('Error al detener la recepción de datos: $e');
      }
    } else {
      _logger.w('No hay recepción de datos activa para detener.');
    }
  }

  void _processReceivedData(List<int> data) {
    // Acumular los datos en un buffer
    for (int byte in data) {
      if (byte == 0x02) {
        // STX
        _buffer.clear();
        _buffer.add(byte);
      } else if (byte == 0x03) {
        // ETX
        _buffer.add(byte);
        _parseBuffer();
        _buffer.clear();
      } else {
        _buffer.add(byte);
      }
    }
  }

  void _parseBuffer() {
    try {
      // Convertir el buffer a String
      String packet = String.fromCharCodes(_buffer);
      _logger.i('Paquete recibido: $packet');

      // Verificar que el paquete empieza con <STX> y termina con <ETX>
      if (_buffer.first == 0x02 && _buffer.last == 0x03) {
        // Extraer el contenido entre <STX> y <ETX>
        String content = packet.substring(1, packet.length - 1);

        _logger.i('Contenido del paquete: $content');

        // Verificar que el paquete es de tipo 'D'
        if (content.startsWith('D,')) {
          // Remover 'D,' y separar los valores
          String dataString = content.substring(2);
          _logger.i('Datos del paquete: $dataString');
          List<String> values = dataString.split(',');

          _logger.i('Valores extraídos: $values');

          if (values.length == 4) {
            int velocidad_scaled = int.tryParse(values[0]) ?? 0;
            int posX_scaled = int.tryParse(values[1]) ?? 0;
            int posY_scaled = int.tryParse(values[2]) ?? 0;
            int yaw_scaled = int.tryParse(values[3]) ?? 0;

            // Desescalar los valores
            double velocidad = velocidad_scaled / 100.0;
            double posX = posX_scaled / 100.0;
            double posY = posY_scaled / 100.0;
            double yaw = yaw_scaled / 100.0;

            // Enviar los datos al StreamController
            _dataController.add({
              'velocidad': velocidad,
              'posX': posX,
              'posY': posY,
              'yaw': yaw,
            });
          } else {
            _logger.w('Cantidad incorrecta de valores en el paquete.');
          }
        } else {
          _logger.w('Paquete no reconocido: $content');
        }
      } else {
        _logger.w('Paquete con formato incorrecto.');
      }
    } catch (e) {
      _logger.e('Error al parsear el paquete: $e');
    }
  }

  Future<void> sendData(String data) async {
    if (_characteristic == null) {
      _logger.e('No se puede enviar datos: característica no inicializada.');
      return;
    }
    try {
      List<int> bytes = data.codeUnits;
      await _characteristic!.write(bytes, withoutResponse: true);
      _logger.i('Datos enviados: $data');
    } catch (e) {
      _logger.e('Error al enviar datos: $e');
    }
  }

  void dispose() {
    _device?.disconnect();
    _dataController.close();
  }
}
