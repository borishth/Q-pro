import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

// ---------------- SIGNATURE CAPTURE SCREEN ----------------

class SignatureCapturePage extends StatefulWidget {
  const SignatureCapturePage({super.key});

  @override
  State<SignatureCapturePage> createState() => _SignatureCapturePageState();
}

class _SignatureCapturePageState extends State<SignatureCapturePage> {
  final SignatureController controller = SignatureController(
    penColor: Colors.black,
    penStrokeWidth: 3,
    exportBackgroundColor: Colors.white,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draw a signature first.')),
      );
      return;
    }

    final bytes = await controller.toPngBytes();
    if (bytes == null || !mounted) return;
    Navigator.of(context).pop(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signature'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            onPressed: controller.clear,
            icon: const Icon(Icons.clear),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Signature(controller: controller, backgroundColor: Colors.white),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: save,
            child: const Text('Save signature'),
          ),
        ),
      ),
    );
  }
}
