import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/call_recording.dart';

class TranscriptChatBubble extends StatelessWidget {
  final TranscriptMessage message;

  const TranscriptChatBubble({
    super.key,
    required this.message,
  });

  bool get isAgent => message.speaker.toLowerCase() == 'agent';

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isAgent ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isAgent ? Colors.blue.shade50 : Colors.green.shade50,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isAgent
                ? const Radius.circular(16)
                : const Radius.circular(4),
            bottomRight: isAgent
                ? const Radius.circular(4)
                : const Radius.circular(16),
          ),
          border: Border.all(
            color: isAgent ? Colors.blue.shade200 : Colors.green.shade200,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Speaker label
              Row(
                mainAxisAlignment:
                    isAgent ? MainAxisAlignment.start : MainAxisAlignment.end,
                children: [
                  Icon(
                    isAgent ? Icons.support_agent : Icons.person,
                    size: 16,
                    color: isAgent ? Colors.blue.shade700 : Colors.green.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isAgent ? 'Agent' : 'Customer',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isAgent ? Colors.blue.shade700 : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Message text
              Text(
                message.text,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 4),
              // Timestamp
              Text(
                DateFormat('HH:mm:ss').format(message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

