import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account.dart';
import 'oa_theme.dart';

import 'i18n.dart';
/// Giriş / üye ol penceresini açar: telefonda alttan, bilgisayarda ortada.
Future<void> showSignIn(
  BuildContext context,
  OAAccount account, {
  required bool mobile,
  bool register = false,
  required void Function(String url) openUrl,
}) {
  final form = _SignInForm(account: account, register: register, openUrl: openUrl);
  if (mobile) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: form,
        ),
      ),
    );
  }
  return showDialog(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: form,
        ),
      ),
    ),
  );
}

class _SignInForm extends StatefulWidget {
  const _SignInForm({required this.account, required this.register, required this.openUrl});
  final OAAccount account;
  final bool register;
  final void Function(String url) openUrl;

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  late bool _register = widget.register;
  bool _codeStep = false;
  bool _busy = false;
  bool _consent = false;
  bool _announce = false;
  String? _msg;
  bool _msgOk = false;
  String? _errorCode;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();

  /// Android: telefonda OA Labs Center kuruluysa tek dokunuşla giriş.
  bool _center = false;

  @override
  void initState() {
    super.initState();
    widget.account.centerAvailable().then((v) {
      if (mounted && v) setState(() => _center = true);
    });
  }

  Future<void> _withCenter() async {
    setState(() => _busy = true);
    _show(null);
    final r = await widget.account.signInWithCenter();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      _show(tx('Giriş yapıldı!', 'Signed in!'), ok: true);
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop();
    } else if (r.error != null) {
      _show(r.message, code: r.error);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _show(String? text, {bool ok = false, String? code}) =>
      setState(() {
        _msg = text;
        _msgOk = ok;
        _errorCode = code;
      });

  Future<void> _send({bool resend = false}) async {
    final email = _email.text.trim();
    if (!resend) {
      if (_register && _name.text.trim().length < 2) return _show(accountError('ad'));
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        return _show(accountError('eposta'));
      }
      if (_register && !_consent) return _show(accountError('onay'));
    }
    setState(() => _busy = true);
    _show(tx('Gönderiliyor…', 'Sending…'));
    final r = await widget.account.start(
      register: _register,
      email: email,
      name: _name.text,
      consent: _consent,
      announce: _announce,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      setState(() {
        _codeStep = true;
        _code.clear();
      });
      _show(resend ? tx('Yeni kod gönderildi.', 'New code sent.') : null, ok: true);
    } else {
      _show(r.message, code: r.error);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) return _show(accountError('kod'));
    setState(() => _busy = true);
    _show(tx('Kontrol ediliyor…', 'Checking…'));
    final r = await widget.account.verify(_email.text, code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      _show(r.created ? tx('Üyeliğin açıldı!', 'Your account is ready!') : tx('Giriş yapıldı!', 'Signed in!'), ok: true);
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop();
    } else {
      _show(r.message, code: r.error);
      _code.selection = TextSelection(baseOffset: 0, extentOffset: _code.text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const OAMark(size: 30),
            const SizedBox(width: 10),
            Text('OA Labs', style: oaDisplay(20)),
            const Spacer(),
            IconButton(
              tooltip: tx('Kapat', 'Close'),
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          _codeStep ? tx('Kodu yaz', 'Enter the code') : (_register ? tx('OA Labs\'e üye ol', 'Join OA Labs') : tx('Giriş yap', 'Sign in')),
          style: oaDisplay(30),
        ),
        const SizedBox(height: 8),
        Text(
          _codeStep
              ? tx('Gelmediyse gereksiz (spam) klasörüne bak.', "If it didn't arrive, check your spam folder.")
              : tx('Ücretsiz ve şifresiz: e-postana gelen kodla giriş yaparsın. Sitedeki hesabınla aynı.', 'Free and password-free: you sign in with a code sent to your email. Same as your account on the website.'),
          style: TextStyle(color: OAColors.text2, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 20),
        if (!_codeStep) ..._step1() else ..._step2(),
        if (_msg != null) ...[
          const SizedBox(height: 14),
          _message(),
        ],
      ],
    );
  }

  List<Widget> _step1() => [
        if (_center && !_register) ...[
          FilledButton(
            onPressed: _busy ? null : _withCenter,
            child: Text(tx('OA Labs Center ile giriş yap', 'Sign in with OA Labs Center')),
          ),
          const SizedBox(height: 8),
          Text(tx('Telefonundaki OA Labs Center hesabınla, kod beklemeden.', 'With your OA Labs Center account on your phone, no code needed.'),
              textAlign: TextAlign.center, style: TextStyle(color: OAColors.muted, fontSize: 13)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Divider(color: OAColors.line)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(tx('ya da e-postayla', 'or with email'), style: TextStyle(color: OAColors.muted, fontSize: 13)),
            ),
            Expanded(child: Divider(color: OAColors.line)),
          ]),
          const SizedBox(height: 18),
        ],
        _tabs(),
        const SizedBox(height: 20),
        if (_register) ...[
          _label(tx('Ad soyad', 'Full name')),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            textInputAction: TextInputAction.next,
            decoration: _box(),
          ),
          const SizedBox(height: 16),
        ],
        _label('E-posta'),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _send(),
          decoration: _box(hint: 'ornek@eposta.com'),
        ),
        if (_register) ...[
          const SizedBox(height: 14),
          _check(
            _consent,
            (v) => setState(() => _consent = v),
            TextSpan(children: [
              TextSpan(
                text: tx('Üyelik aydınlatma metnini', 'I have read the membership privacy notice'),
                style: TextStyle(
                    color: OAColors.accent,
                    decoration: TextDecoration.underline,
                    decorationColor: OAColors.accent),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    Navigator.of(context).pop();
                    widget.openUrl('${OAAccount.site}/gizlilik/#uyelik');
                  },
              ),
               TextSpan(
                  text:
                      tx(' okudum; adımın ve e-posta adresimin üyelik için işlenmesini kabul ediyorum.', ' and agree to my name and email address being processed for my membership.')),
            ]),
          ),
          _check(
            _announce,
            (v) => setState(() => _announce = v),
             TextSpan(
                text:
                    tx('Yeni uygulamalar ve önemli güncellemeler için e-posta almak istiyorum. (İsteğe bağlı, istediğin zaman kapatabilirsin.)', "I'd like to get emails about new apps and important updates. (Optional; you can turn this off any time.)")),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: Text(tx('Kod gönder', 'Send code')),
        ),
      ];

  List<Widget> _step2() => [
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: _email.text.trim(),
                style: TextStyle(color: OAColors.text, fontWeight: FontWeight.w600)),
             TextSpan(text: tx(' adresine 6 haneli bir kod gönderdik.', ' — we sent a 6-digit code to this address.')),
          ]),
          style: TextStyle(color: OAColors.text2, fontSize: 15),
        ),
        const SizedBox(height: 16),
        _label(tx('Kod', 'Code')),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          textAlign: TextAlign.center,
          style: oaDisplay(30).copyWith(letterSpacing: 12),
          onChanged: (v) {
            if (v.length == 6 && !_busy) _verify();
          },
          onSubmitted: (_) => _verify(),
          decoration: _box(radius: OARadius.md),
        ),
        const SizedBox(height: 6),
        Text(tx('Kod 10 dakika geçerli.', 'The code is valid for 10 minutes.'), style: TextStyle(color: OAColors.faint, fontSize: 13)),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: Text(tx('Onayla', 'Confirm')),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
                onPressed: _busy ? null : () => _send(resend: true),
                child: Text(tx('Kodu yeniden gönder', 'Resend code'))),
            TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _codeStep = false;
                          _msg = null;
                        }),
                child: Text(tx('E-postayı değiştir', 'Change email'))),
          ],
        ),
      ];

  Widget _tabs() {
    Widget tab(String label, bool on, VoidCallback onTap) => Expanded(
          child: Material(
            color: on ? OAColors.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: on ? OAColors.text : OAColors.muted)),
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: OAColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OAColors.border),
      ),
      child: Row(
        children: [
          tab(tx('Giriş yap', 'Sign in'), !_register, () => setState(() {
                _register = false;
                _msg = null;
              })),
          const SizedBox(width: 4),
          tab(tx('Üye ol', 'Sign up'), _register, () => setState(() {
                _register = true;
                _msg = null;
              })),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      );

  InputDecoration _box({String? hint, double radius = OARadius.md}) => InputDecoration(
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: OAColors.border2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: OAColors.accent),
        ),
      );

  Widget _check(bool value, ValueChanged<bool> onChanged, InlineSpan text) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(text,
                  style: TextStyle(fontSize: 14, height: 1.5, color: OAColors.text2)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message() {
    final err = !_msgOk && _msg != tx('Gönderiliyor…', 'Sending…') && _msg != tx('Kontrol ediliyor…', 'Checking…');
    final switchTo = _errorCode == 'uye-yok'
        ? tx('Üye ol', 'Sign up')
        : _errorCode == 'uye-var'
            ? tx('Giriş yap', 'Sign in')
            : null;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          _msg!,
          style: TextStyle(
            fontSize: 15,
            color: _msgOk ? OAColors.green : (err ? OAColors.danger : OAColors.muted),
          ),
        ),
        if (switchTo != null)
          TextButton(
            onPressed: () => setState(() {
              _register = _errorCode == 'uye-yok';
              _msg = null;
            }),
            child: Text(switchTo),
          ),
      ],
    );
  }
}

/// Giriş yapmış üyenin özeti: ad, e-posta, hesabı yönet, çıkış.
class AccountSummary extends StatelessWidget {
  const AccountSummary({
    super.key,
    required this.account,
    required this.onManage,
    required this.onLogout,
  });
  final OAAccount account;
  final VoidCallback onManage;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final u = account.user!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            OAAvatar(name: u.name, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  Text(u.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: OAColors.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: onManage,
          icon: const Icon(Icons.manage_accounts_outlined, size: 20),
          label: Text(tx('Hesabımı yönet', 'Manage my account')),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onLogout,
          icon: Icon(Icons.logout, size: 20, color: OAColors.danger),
          label: Text(tx('Çıkış yap', 'Sign out'), style: TextStyle(color: OAColors.danger)),
        ),
      ],
    );
  }
}
