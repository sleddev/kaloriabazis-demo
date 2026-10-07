import 'package:flutter/material.dart';

import '../api/kb_client.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Add meg a felhasználóneved és a jelszavad.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).login(_user.text, _pass.text);
    } on KbException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = AppScope.of(context).authNotice;
    return Scaffold(
      backgroundColor: Palette.inkCard,
      body: Stack(
        children: [
          // Decorative rings in the background.
          Positioned(
            top: -80,
            right: -90,
            child: Opacity(
              opacity: 0.9,
              child: CalorieRing(
                eaten: 1500,
                goal: 2000,
                size: 300,
                stroke: 30,
                track: Colors.white10,
              ),
            ),
          ),
          Positioned(
            top: 150,
            left: -60,
            child: Opacity(
              opacity: 0.35,
              child: CalorieRing(
                eaten: 700,
                goal: 2000,
                size: 140,
                stroke: 14,
                track: Colors.white10,
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight - 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 200),
                      Text(
                        'kalóri.',
                        style: numberStyle(
                          56,
                          color: Colors.white,
                        ).copyWith(letterSpacing: -2),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'A kaloriabazis.hu naplód,\nzsebméretben.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 36),
                      if (notice != null && _error == null) ...[
                        _Banner(notice, color: Palette.carbs),
                        const SizedBox(height: 14),
                      ],
                      _field(
                        _user,
                        'Felhasználónév',
                        Icons.person_rounded,
                        action: TextInputAction.next,
                        autofill: const [AutofillHints.username],
                      ),
                      const SizedBox(height: 12),
                      _field(
                        _pass,
                        'Jelszó',
                        Icons.lock_rounded,
                        obscure: _obscure,
                        action: TextInputAction.done,
                        autofill: const [AutofillHints.password],
                        onSubmit: (_) => _submit(),
                        suffix: IconButton(
                          color: Colors.white54,
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: _error == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: _Banner(_error!, color: Palette.over),
                              ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: Palette.ember,
                          disabledBackgroundColor: Palette.ember.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Bejelentkezés'),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Nincs még fiókod? Regisztrálj a kaloriabazis.hu oldalon.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String hint,
    IconData icon, {
    bool obscure = false,
    TextInputAction? action,
    Iterable<String>? autofill,
    ValueChanged<String>? onSubmit,
    Widget? suffix,
  }) => TextField(
    controller: c,
    obscureText: obscure,
    textInputAction: action,
    autofillHints: autofill,
    onSubmitted: onSubmit,
    autocorrect: false,
    enableSuggestions: false,
    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    cursorColor: Palette.ember,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.07),
      prefixIcon: Icon(icon, color: Colors.white54),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Palette.ember, width: 1.5),
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(Icons.info_rounded, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
          ),
        ),
      ],
    ),
  );
}
