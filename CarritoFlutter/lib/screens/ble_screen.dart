import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import '../services/ble_service.dart';
import '../utils/permissions.dart';
import 'package:logger/logger.dart';

class BLEScreen extends StatefulWidget {
  const BLEScreen({Key? key}) : super(key: key);

  @override
  BLEScreenState createState() => BLEScreenState();
}

class BLEScreenState extends State<BLEScreen>
    with SingleTickerProviderStateMixin {
  final BLEService _bleService = BLEService();
  final Logger _logger = Logger();
  String _connectionText = 'Buscando dispositivos...';

  // Controladores para los campos configurables
  final TextEditingController _speedController = TextEditingController();
  final TextEditingController _distanceController = TextEditingController();

  // Indicadores de datos
  double _currentSpeed = 0.0;
  double _currentDistanceX = 0.0;
  double _currentDistanceY = 0.0;
  double _currentAngle = 0.0;

  // Controlador de animaciones
  late AnimationController _animationController;

  // Agregar un formulario global key para validación
  final _formKey = GlobalKey<FormState>();

  // Variables para manejar la conexión
  bool _isConnecting = false;

  // Variable para manejar el modo
  bool _isManualMode = false; // Por defecto es modo automático

  @override
  void initState() {
    super.initState();
    _initialize();

    // Inicializar el controlador de animaciones
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animationController.forward();

    // Suscribirse al stream de datos
    _bleService.dataStream.listen((data) {
      setState(() {
        _currentSpeed = data['velocidad'] ?? _currentSpeed;
        _currentDistanceX = data['posX'] ?? _currentDistanceX;
        _currentDistanceY = data['posY'] ?? _currentDistanceY;
        _currentAngle = data['yaw'] ?? _currentAngle;
      });
    });
  }

  Future<void> _initialize() async {
    bool permissionsGranted = await requestPermissions();
    if (permissionsGranted) {
      _startScan();
    } else {
      setState(() {
        _connectionText = 'Permisos necesarios no concedidos.';
      });
      _logger.e('Permisos necesarios no concedidos.');
    }
  }

  void _startScan() {
    setState(() {
      _connectionText = 'Escaneando dispositivos BLE...';
      _isConnecting = true;
    });
    _bleService.scanForDevices(
      onDeviceFound: (deviceName) {
        setState(() {
          _connectionText = 'Conectado a $deviceName';
          _isConnecting = false;
        });
        _sendModeCommand(); // Enviar comando de modo al conectar

        if (_isManualMode) {
          // Modo Manual: No leer datos
          _bleService.stopListening();
        } else {
          // Modo Automático: Leer datos
          _bleService.startListening();
        }
      },
      onScanComplete: (found) {
        if (!found) {
          setState(() {
            _connectionText = 'Dispositivo no encontrado. Intenta nuevamente.';
            _isConnecting = false;
          });
          _logger.w('Dispositivo no encontrado después de escanear.');
        }
      },
    );
  }

  Future<void> _sendModeCommand() async {
    String modeCommand =
        _isManualMode ? '\x02MODE:MANUAL\x03' : '\x02MODE:AUTO\x03';

    // Asegúrate de que sendData sea una función asíncrona que retorne un Future
    await _bleService.sendData(modeCommand);

    _logger.i('Enviado comando de modo: ${_isManualMode ? 'MANUAL' : 'AUTO'}.');
  }

  void _sendData() {
    if (_isManualMode) {
      if (_validateInputs()) {
        // Parsear los valores de entrada
        final speed = double.parse(_speedController.text);
        final angle = double.parse(_distanceController
            .text); // Asumiendo que 'distance' es para ángulo

        // Escalar los valores multiplicando por 100 y convertir a enteros
        int speedInt = (speed * 10000).toInt(); // Ejemplo: 50.00 -> 5000
        int angleInt = (angle * 10000).toInt(); // Ejemplo: 90.00 -> 9000

        // Formatear los enteros como cadenas de 5 dígitos, rellenando con ceros a la izquierda
        String speedStr = speedInt.toString(); // "05000"
        String angleStr = angleInt.toString(); // "09000"

        // Construir el paquete con STX, identificador 'M', ángulo, velocidad y ETX
        String dataToSend =
            '\x02M$angleStr,$speedStr\x03'; // "\x02M09000,05000\x03"

        // Enviar el paquete vía BLE
        _bleService.sendData(dataToSend);

        // Log para depuración
        _logger.i('Paquete enviado: $dataToSend');

        // Iniciar animación si es necesario
        _animationController.forward(from: 0);
      }
    } else {
      _logger.w('No se pueden enviar datos en modo automático.');
    }
  }

  bool _validateInputs() {
    if (!_formKey.currentState!.validate()) {
      return false;
    }

    // Validar ángulo
    double angle = double.tryParse(_distanceController.text) ?? double.nan;
    if (angle.isNaN || angle < -80.00 || angle > 80.00) {
      _logger.w('Ángulo debe estar entre -80.00 y +80.00 grados.');
      return false;
    }

    // Validar velocidad
    double speed = double.tryParse(_speedController.text) ?? double.nan;
    if (speed.isNaN || speed < 0.00 || speed > 1000.00) {
      _logger.w('Velocidad debe estar entre 0.00 y 1000.00 unidades.');
      return false;
    }

    return true;
  }

  void _stop() {
    // Comando para detener el carrito
    String dataToSend = '\x02P\x03'; // Comando Stop
    _bleService.sendData(dataToSend);
    _logger.i('Enviado comando STOP.');
  }

  void _onJoystickMove(StickDragDetails details) {
    if (_isManualMode) {
      final currentTime = DateTime.now();
      // Obtener los valores de grados y distancia del joystick
      double degrees = details.x; // Asegúrate de que 'x' representa el ángulo
      double distance =
          details.y; // Asegúrate de que 'y' representa la velocidad

      // Escalar los valores multiplicando por 100 y convertir a enteros
      int angleInt = (degrees * 100).toInt(); // Ejemplo: 90.00 -> 9000
      int speedInt = (distance * 1000).toInt(); // Ejemplo: 50.00 -> 5000

      // Formatear los enteros como cadenas de 6 dígitos, rellenando con ceros a la izquierda
      String angleStr = angleInt.toString(); // "009000"
      String speedStr = speedInt.toString(); // "005000"

      // Construir el paquete con STX, identificador 'M', ángulo, velocidad y ETX
      String dataToSend =
          '\x02M$angleStr,$speedStr\x03'; // "\x02M009000,005000\x03"

      // Enviar el paquete vía BLE
      _bleService.sendData(dataToSend);
      _logger.i('Paquete enviado via joystick: $dataToSend');

      // Actualizar el último tiempo de envío
    } else {
      _logger.w('No se pueden enviar comandos en modo automático.');
    }
  }

  @override
  void dispose() {
    _bleService.dispose();
    _speedController.dispose();
    _distanceController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(), // Usamos el método _buildAppBar()
      body: SafeArea(
        child: _bleService.isConnected
            ? (_isManualMode ? _buildManualModeBody() : _buildConnectedBody())
            : _buildDisconnectedBody(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Control de Carrito BLE'),
      backgroundColor: const Color(0xFF0D47A1),
      elevation: 0,
      centerTitle: true,
      actions: [
        IconButton(
          icon: Icon(_isManualMode ? Icons.settings : Icons.drive_eta),
          onPressed: () async {
            setState(() {
              _isManualMode = !_isManualMode;
            });

            await _sendModeCommand(); // Enviar comando de modo al carrito

            // Introducir un pequeño retraso para asegurar que el dispositivo procese el comando
            await Future.delayed(const Duration(milliseconds: 500));

            if (_isManualMode) {
              // Modo Manual: No leer datos, solo enviar
              _bleService.stopListening();
            } else {
              // Modo Automático: Leer datos, no enviar (excepto comando de modo)
              _bleService.startListening();
            }
          },
        ),
      ],
    );
  }

  Widget _buildManualModeBody() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildConnectionStatus(),
        const SizedBox(height: 20),
        Joystick(
          mode: JoystickMode.all,
          listener: _onJoystickMove,
        ),
        const SizedBox(height: 20),
        _buildElevatedButton('Detener', const Color(0xFFE53935), _stop),
      ],
    );
  }

  Widget _buildConnectedBody() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildConnectionStatus(),
            const SizedBox(height: 20),
            _buildIndicatorsGrid(),
            const SizedBox(height: 20),
            _buildConfigFields(),
            const SizedBox(height: 20),
            _buildControlButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildDisconnectedBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildConnectionStatus(),
            const SizedBox(height: 20),
            _buildElevatedButton(
                'Reescanear', const Color(0xFFFFA726), _startScan),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(seconds: 1),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _bleService.isConnected
                ? const Color(0xFF66BB6A) // Verde
                : _isConnecting
                    ? const Color(0xFFFFA726) // Naranja durante la conexión
                    : const Color(0xFFE53935), // Rojo
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _connectionText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF212121),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIndicatorsGrid() {
    return Wrap(
      spacing: 16.0,
      runSpacing: 16.0,
      alignment: WrapAlignment.center,
      children: [
        _buildAnimatedIndicatorCard(
            "Velocidad",
            "${_currentSpeed.toStringAsFixed(2)} u",
            Icons.speed,
            _currentSpeed,
            1000),
        _buildAnimatedIndicatorCard(
            "Posición X",
            "${_currentDistanceX.toStringAsFixed(2)} cm",
            Icons.straighten,
            _currentDistanceX,
            1000),
        _buildAnimatedIndicatorCard(
            "Posición Y",
            "${_currentDistanceY.toStringAsFixed(2)} cm",
            Icons.height,
            _currentDistanceY,
            1000),
        _buildAnimatedIndicatorCard(
            "Ángulo",
            "${_currentAngle.toStringAsFixed(2)}°",
            Icons.rotate_90_degrees_ccw,
            _currentAngle,
            360),
      ],
    );
  }

  Widget _buildAnimatedIndicatorCard(String title, String value, IconData icon,
      double currentValue, double maxValue) {
    double progress = (currentValue.abs()) / maxValue;
    progress = progress.clamp(0.0, 1.0);

    bool isNegative = currentValue < 0;
    Color progressColor = isNegative
        ? const Color(0xFFE53935) // Rojo para negativos
        : const Color(0xFF43A047); // Verde para positivos

    return SizedBox(
      width: (MediaQuery.of(context).size.width - 48) / 2,
      child: ScaleTransition(
        scale: CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeOutBack,
        ),
        child: Card(
          color: Colors.white,
          elevation: 4,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularPercentIndicator(
                  radius: 40.0,
                  lineWidth: 6.0,
                  percent: progress,
                  center: Icon(
                    icon,
                    color: const Color(0xFF0D47A1),
                    size: 32,
                  ),
                  backgroundColor: Colors.grey[200]!,
                  progressColor: progressColor,
                  circularStrokeCap: CircularStrokeCap.round,
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF757575),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfigFields() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _buildConfigField("Velocidad (0-1000)", _speedController),
          const SizedBox(height: 10),
          _buildConfigField("Distancia (cm)", _distanceController),
        ],
      ),
    );
  }

  Widget _buildConfigField(String label, TextEditingController controller) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Color(0xFF212121)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF0D47A1)),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFF0D47A1)),
          borderRadius: BorderRadius.circular(10.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFF0D47A1)),
          borderRadius: BorderRadius.circular(10.0),
        ),
        errorStyle: const TextStyle(color: Color(0xFFE53935)),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Por favor ingrese $label';
        }
        if (double.tryParse(value) == null) {
          return 'Ingrese un número válido';
        }
        return null;
      },
    );
  }

  Widget _buildControlButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildElevatedButton(
              'Iniciar', const Color(0xFF0D47A1), _sendData),
        ),
        const SizedBox(width: 16),
        Expanded(
          child:
              _buildElevatedButton('Detener', const Color(0xFFE53935), _stop),
        ),
      ],
    );
  }

  Widget _buildElevatedButton(
      String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: _bleService.isConnected ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 5,
        shadowColor: Colors.black45,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
