import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

/// UI-only currency converter with dummy fixed exchange rates.
class CurrencyConverterScreen extends StatefulWidget {
  const CurrencyConverterScreen({super.key});

  @override
  State<CurrencyConverterScreen> createState() =>
      _CurrencyConverterScreenState();
}

class _CurrencyConverterScreenState extends State<CurrencyConverterScreen> {
  final _controller = TextEditingController(text: '100');
  String _from = 'MYR';
  String _to = 'USD';

  static final _rates = {
    'MYR': 1.0,
    'USD': 0.21,
    'SGD': 0.29,
    'EUR': 0.20,
    'GBP': 0.17,
    'JPY': 33.4,
    'CNY': 1.55,
  };

  double get _amount => double.tryParse(_controller.text.trim()) ?? 0;

  double get _result => _amount / _rates[_from]! * _rates[_to]!;

  void _swap() {
    setState(() {
      final tmp = _from;
      _from = _to;
      _to = tmp;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('utilities_currency_converter_title'),
              subtitle: tr('utilities_currency_converter_subtitle'),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Container(
                    padding: EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: context.colors.ink.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _CurrencyRow(
                          currency: _from,
                          controller: _controller,
                          editable: true,
                          onChanged: (v) => setState(() {}),
                          onCurrencyTap: () => _pickCurrency(
                            context,
                            (c) => setState(() => _from = c),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Material(
                            color: context.colors.ink,
                            shape: CircleBorder(),
                            child: InkWell(
                              customBorder: CircleBorder(),
                              onTap: _swap,
                              child: Padding(
                                padding: EdgeInsets.all(10),
                                child: Icon(
                                  Icons.swap_vert_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _CurrencyRow(
                          currency: _to,
                          value: _result.toStringAsFixed(2),
                          editable: false,
                          onCurrencyTap: () => _pickCurrency(
                            context,
                            (c) => setState(() => _to = c),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  Container(
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '1 $_from = ${(_rates[_to]! / _rates[_from]!).toStringAsFixed(4)} $_to',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickCurrency(BuildContext context, ValueChanged<String> onPicked) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _rates.keys.map((c) {
              return ListTile(
                title: Text(
                  c,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  onPicked(c);
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({
    required this.currency,
    required this.onCurrencyTap,
    this.controller,
    this.value,
    this.editable = false,
    this.onChanged,
  });

  final String currency;
  final TextEditingController? controller;
  final String? value;
  final bool editable;
  final ValueChanged<String>? onChanged;
  final VoidCallback onCurrencyTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: editable
              ? TextField(
                  controller: controller,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  onChanged: onChanged,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(border: InputBorder.none),
                )
              : Text(
                  value ?? '0',
                  style: TextStyle(
                    color: context.colors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        Material(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onCurrencyTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Text(
                    currency,
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.expand_more_rounded,
                    color: context.colors.muted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
