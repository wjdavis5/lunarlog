/// Branded "Sign in with Google" button (#2 U4; KTD6, R12, AS8).
///
/// No official Flutter widget exists, so this draws the light-theme
/// rectangular button from Google's branding guidelines
/// (https://developers.google.com/identity/branding-guidelines): 40 dp
/// tall, white fill, a 1 dp `#747775` stroke with 4 dp corners, `#1F1F1F`
/// medium 14 pt label, and the unmodified "G" mark from
/// `assets/branding/google_g_logo.png` on a white pad with 12 dp of left
/// padding. Press feedback is the default ink overlay only; a null
/// [onPressed] renders the disabled state at reduced opacity.
library;

import 'package:flutter/material.dart';

const Color _kGoogleStroke = Color(0xFF747775);
const Color _kGoogleText = Color(0xFF1F1F1F);
const String _kGoogleLabel = 'Sign in with Google';

class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, required this.onPressed});

  /// Null disables the button (busy screen), keeping the branding intact.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: _kGoogleLabel,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : 0.38,
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: _kGoogleStroke),
              borderRadius: BorderRadius.circular(4),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                height: 40,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 12, right: 10),
                      child: Image(
                        image: AssetImage('assets/branding/google_g_logo.png'),
                        width: 18,
                        height: 18,
                      ),
                    ),
                    const Text(
                      _kGoogleLabel,
                      style: TextStyle(
                        color: _kGoogleText,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
