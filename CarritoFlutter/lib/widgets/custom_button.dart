import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color? color; // Parámetro opcional para el color

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.color, // Aceptar color opcional
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color ??
            Theme.of(context)
                .primaryColor, // Usar el color especificado o el color primario por defecto
      ),
      child: Text(text),
    );
  }
}
