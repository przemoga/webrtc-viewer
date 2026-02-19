import 'package:flutter/material.dart';
import '../../style.dart';

class PasswordDialog extends StatefulWidget {
  final String initialValue;

  const PasswordDialog({super.key, required this.initialValue});

  static Future<String?> show(BuildContext context, {required String initialValue}) {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PasswordDialog(initialValue: initialValue),
    );
  }

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  late final TextEditingController _pwCtrl;
  bool _showPw = false;

  @override
  void initState() {
    super.initState();
    _pwCtrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppStyles.surfaceColor,
      title: Text(
        "Room password",
        style: AppStyles.subTitleLine.copyWith(color: AppStyles.whiteColor),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "If the room is public, leave it empty.",
            style: AppStyles.captionLine.copyWith(
              color: AppStyles.whiteColor.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pwCtrl,
            autofocus: true,
            obscureText: !_showPw,
            style: const TextStyle(color: AppStyles.whiteColor),
            decoration: InputDecoration(
              labelText: "Password (optional)",
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPw = !_showPw),
              ),
            ),
            onSubmitted: (_) => Navigator.of(context).pop(_pwCtrl.text.trim()),
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(null),
          style: AppStyles.primaryButtonStyle(AppStyles.themeColor),
          child: Text("Cancel", style: AppStyles.buttonTextStyle),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_pwCtrl.text.trim()),
          style: AppStyles.primaryButtonStyle(AppStyles.themeColor),
          child: Text("Connect", style: AppStyles.buttonTextStyle),
        ),
      ],
    );
  }
}
