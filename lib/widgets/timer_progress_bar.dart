import 'package:flutter/material.dart';
import 'package:alarmacacao5_0/services/real_time_timer.dart';

class TimerProgressBar extends StatefulWidget {
  final int totalDuration;
  final VoidCallback? onTimerComplete;
  final Color? progressColor;
  final Color? backgroundColor;
  final double height;
  final TextStyle? textStyle;

  const TimerProgressBar({
    Key? key,
    required this.totalDuration,
    this.onTimerComplete,
    this.progressColor,
    this.backgroundColor,
    this.height = 8.0,
    this.textStyle,
  }) : super(key: key);

  @override
  State<TimerProgressBar> createState() => _TimerProgressBarState();
}

class _TimerProgressBarState extends State<TimerProgressBar> {
  final RealTimeTimer _timer = RealTimeTimer();
  int _elapsedTime = 0;
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _initializeTimer();
  }

  Future<void> _initializeTimer() async {
    await _timer.loadTimerState();
    
    _timer.onTimeUpdate = (elapsed) {
      if (mounted) {
        setState(() {
          _elapsedTime = elapsed;
          _isActive = _timer.isTimerActive();
        });
      }
    };

    _timer.onTimerComplete = () {
      if (mounted) {
        setState(() {
          _isActive = false;
        });
        if (widget.onTimerComplete != null) {
          widget.onTimerComplete!();
        }
      }
    };

    setState(() {
      _elapsedTime = _timer.getElapsedTime();
      _isActive = _timer.isTimerActive();
    });
  }

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  double get _progress {
    if (widget.totalDuration <= 0) return 0.0;
    return (_elapsedTime / widget.totalDuration).clamp(0.0, 1.0);
  }

  String get _formattedTime {
    final remaining = widget.totalDuration - _elapsedTime;
    final hours = (remaining ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((remaining % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: _progress,
          backgroundColor: widget.backgroundColor ?? Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(
            widget.progressColor ?? Theme.of(context).primaryColor,
          ),
          minHeight: widget.height,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tiempo transcurrido: ${_elapsedTime ~/ 3600}h ${(_elapsedTime % 3600) ~/ 60}m',
              style: widget.textStyle ?? Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              _formattedTime,
              style: widget.textStyle ?? Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
