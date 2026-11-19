import 'package:material_ui/material_ui.dart';

import '../services/traccar_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _markerLabel;
  late bool _satelliteDefault;

  @override
  void initState() {
    super.initState();
    final service = TraccarService.instance;
    _markerLabel = service.markerLabel;
    _satelliteDefault = service.satelliteView;
  }

  Future<void> _showChangePasswordDialog() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (updated == true && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const LoginScreen(),
        ),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = TraccarService.instance;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF007AA5),
        foregroundColor: Colors.white,
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Settings',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Map Label'),
                  value: _markerLabel,
                  onChanged: (val) async {
                    setState(() => _markerLabel = val);
                    await service.setMarkerLabel(val);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Satellite Default'),
                  value: _satelliteDefault,
                  onChanged: (val) async {
                    setState(() => _satelliteDefault = val);
                    await service.setSatelliteView(val);
                  },
                ),
                const Divider(height: 16),
                InkWell(
                  onTap: _showChangePasswordDialog,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          'Change Password',
                          style: TextStyle(fontSize: 15, color: Colors.black),
                        ),
                        Icon(Icons.chevron_right, color: Colors.black45),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final TextEditingController _pass1Ctrl = TextEditingController();
  final TextEditingController _pass2Ctrl = TextEditingController();
  String _errorText = '';
  bool _submitting = false;

  @override
  void dispose() {
    _pass1Ctrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (_submitting) return;
    if (_pass1Ctrl.text.isEmpty || _pass1Ctrl.text != _pass2Ctrl.text) {
      setState(() {
        _errorText = _pass1Ctrl.text.isEmpty
            ? 'Inserisci una password'
            : 'Password not Same';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = '';
    });
    try {
      final service = TraccarService.instance;
      await service.updatePassword(_pass1Ctrl.text);
      await service.logout();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = 'Password not updated: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _pass1Ctrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New Password'),
            onChanged: (_) {
              setState(() {
                _errorText = _pass1Ctrl.text != _pass2Ctrl.text
                    ? 'Password not Same'
                    : '';
              });
            },
          ),
          TextField(
            controller: _pass2Ctrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Retype Password'),
            onChanged: (_) {
              setState(() {
                _errorText = _pass1Ctrl.text != _pass2Ctrl.text
                    ? 'Password not Same'
                    : '';
              });
            },
          ),
          if (_errorText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _errorText,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _onSubmit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
