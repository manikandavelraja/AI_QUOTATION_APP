import 'package:flutter/material.dart';

/// Shared AI disclaimer widget for contract management and other AI-generated content.
class AIDisclaimer extends StatelessWidget {
  final double? confidenceScore;

  const AIDisclaimer({super.key, this.confidenceScore});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 16,
        vertical: isMobile ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.yellow.shade50,
        border: Border(
          top: BorderSide(color: Colors.yellow.shade200, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            size: isMobile ? 16 : 18,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: isMobile ? 11 : 12,
                  color: Colors.amber.shade900,
                  fontStyle: FontStyle.italic,
                ),
                children: const [
                  TextSpan(
                    text:
                        'Note: Portions of this analysis are AI-generated, please ',
                  ),
                  TextSpan(
                    text: 'double-check for accuracy.',
                    style: TextStyle(decoration: TextDecoration.underline),
                  ),
                ],
              ),
            ),
          ),
          if (confidenceScore != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Confidence: ${(confidenceScore! * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
