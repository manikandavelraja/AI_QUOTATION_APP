import 'package:flutter/material.dart';
import 'pdf_analysis_screen.dart';
import 'image_analysis_screen.dart';
import '../../core/theme/app_theme.dart';

/// Contract Management hub: two buttons – PDF Analysis and Image Analysis.
/// Replaces the previous single PDF Analysis view.
enum _ContractView { hub, pdf, image }

class ContractManagementHubScreen extends StatefulWidget {
  const ContractManagementHubScreen({super.key});

  @override
  State<ContractManagementHubScreen> createState() =>
      _ContractManagementHubScreenState();
}

class _ContractManagementHubScreenState extends State<ContractManagementHubScreen> {
  _ContractView _view = _ContractView.hub;

  void _showPdfAnalysis() {
    setState(() => _view = _ContractView.pdf);
  }

  void _showImageAnalysis() {
    setState(() => _view = _ContractView.image);
  }

  void _backToHub() {
    setState(() => _view = _ContractView.hub);
  }

  @override
  Widget build(BuildContext context) {
    if (_view == _ContractView.pdf) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _backToHub,
          ),
          title: const Text('PDF Analysis'),
        ),
        body: const PDFAnalysisScreen(showAppBar: false),
      );
    }
    if (_view == _ContractView.image) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _backToHub,
          ),
          title: const Text('Image Analysis'),
        ),
        body: const ImageAnalysisScreen(showAppBar: false),
      );
    }

    // Hub: two buttons
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                'Contract Management',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose an option to analyze documents or images.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                onPressed: _showPdfAnalysis,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF Analysis'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: AppTheme.iconGraphGreen,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showImageAnalysis,
                icon: const Icon(Icons.image),
                label: const Text('Image Analysis'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: AppTheme.iconGraphGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
