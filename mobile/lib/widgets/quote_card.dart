import 'package:flutter/material.dart';
import '../models/stock_models.dart';

class QuoteCard extends StatelessWidget {
  final QuoteData quote;
  final bool compact;

  const QuoteCard({super.key, required this.quote, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isUp = quote.change >= 0;
    final color = isUp ? const Color(0xFFef5350) : const Color(0xFF26a69a);

    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        quote.name.isNotEmpty ? quote.name : quote.code,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        quote.code,
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  quote.price.toStringAsFixed(2),
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${quote.change >= 0 ? '+' : ''}${quote.change.toStringAsFixed(2)}',
                      style: TextStyle(color: color, fontSize: 13),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${quote.changePct >= 0 ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
                      style: TextStyle(color: color, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 价格和涨跌
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quote.name.isNotEmpty ? quote.name : quote.code,
                        style: const TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        quote.price.toStringAsFixed(2),
                        style: TextStyle(
                          color: color,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${quote.change >= 0 ? '+' : ''}${quote.change.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${quote.changePct >= 0 ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(color: Colors.white12),

            // 交易数据网格
            Row(
              children: [
                _buildField('开盘', quote.open.toStringAsFixed(2)),
                _buildField('昨收', quote.preClose.toStringAsFixed(2)),
                _buildField('最高', quote.high.toStringAsFixed(2)),
                _buildField('最低', quote.low.toStringAsFixed(2)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildField('成交量', _formatNum(quote.volume)),
                _buildField('成交额', _formatAmount(quote.amount)),
                _buildField('振幅', '${quote.amplitude.toStringAsFixed(2)}%'),
                _buildField('换手', '${quote.turnover.toStringAsFixed(2)}%'),
              ],
            ),

            if (quote.pe > 0 || quote.pb > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (quote.pe > 0) _buildField('PE', quote.pe.toStringAsFixed(2)),
                  if (quote.pb > 0) _buildField('PB', quote.pb.toStringAsFixed(2)),
                  if (quote.totalMarketCap > 0)
                    _buildField('总市值', _formatAmount(quote.totalMarketCap)),
                  if (quote.circulatingMarketCap > 0)
                    _buildField('流通市值', _formatAmount(quote.circulatingMarketCap)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _formatNum(double val) {
    if (val >= 100000000) {
      return '${(val / 100000000).toStringAsFixed(2)}亿';
    } else if (val >= 10000) {
      return '${(val / 10000).toStringAsFixed(2)}万';
    }
    return val.toStringAsFixed(0);
  }

  String _formatAmount(double val) {
    if (val >= 100000000) {
      return '${(val / 100000000).toStringAsFixed(2)}亿';
    } else if (val >= 10000) {
      return '${(val / 10000).toStringAsFixed(2)}万';
    }
    return val.toStringAsFixed(2);
  }
}