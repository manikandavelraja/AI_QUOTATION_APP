import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';

class LanguageToggleWidget extends StatelessWidget {
  const LanguageToggleWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageProvider>(
      builder: (context, languageProvider, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Language',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _LanguageButton(
                        label: 'English',
                        language: AppLanguage.english,
                        isSelected: languageProvider.currentLanguage == AppLanguage.english,
                        onTap: () {
                          languageProvider.setLanguage(AppLanguage.english);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _LanguageButton(
                        label: 'தமிழ்',
                        language: AppLanguage.tamil,
                        isSelected: languageProvider.currentLanguage == AppLanguage.tamil,
                        onTap: () {
                          languageProvider.setLanguage(AppLanguage.tamil);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _LanguageButton(
                        label: 'हिंदी',
                        language: AppLanguage.hindi,
                        isSelected: languageProvider.currentLanguage == AppLanguage.hindi,
                        onTap: () {
                          languageProvider.setLanguage(AppLanguage.hindi);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LanguageButton extends StatelessWidget {
  final String label;
  final AppLanguage language;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageButton({
    required this.label,
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
