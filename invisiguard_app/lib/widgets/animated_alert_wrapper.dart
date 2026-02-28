import 'package:flutter/material.dart';

class AnimatedAlertWrapper extends StatefulWidget {
  final Widget child;

  const AnimatedAlertWrapper({super.key, required this.child});

  @override
  State<AnimatedAlertWrapper> createState() => _AnimatedAlertWrapperState();
}

class _AnimatedAlertWrapperState extends State<AnimatedAlertWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _slideAnimation =
        Tween<Offset>(
          begin: const Offset(0, -0.05),
          end: const Offset(0, 0.05),
        ).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
        );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(position: _slideAnimation, child: widget.child);
  }
}
