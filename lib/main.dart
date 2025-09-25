import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';

import 'services/image_compressor.dart';
import 'services/uploader.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Compress Demo',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(title: 'Image Compress Demo'),
      // Localization delegates for Material/Cupertino/Widgets
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[
        Locale('en'),
        Locale('ar'),
        Locale('he'),
        Locale('fa'),
        Locale('ur'),
        Locale('zh'),
      ],
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final ImagePicker _picker = ImagePicker();
  File? _originalFile;
  File? _compressedFile;
  int? _originalBytes;
  int? _compressedBytes;
  bool _uploading = false;
  bool _includeOriginal = true;
  int _targetKB = 800;
  int? _qualityUsed;
  final ImageUploaderService _uploader = ImageUploaderService();
  int? _compressDurationMs;

  @override
  Widget build(BuildContext context) {
    final TextDirection dir = Directionality.of(context);
    final EdgeInsetsGeometry pagePadding = const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16);
    return Scaffold(
      appBar: AppBar(backgroundColor: Theme.of(context).colorScheme.inversePrimary, title: Text(widget.title)),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () async {
          SystemChannels.textInput.invokeMethod('TextInput.hide');
        },
        child: SingleChildScrollView(
          padding: pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                textDirection: dir,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _onPick,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('选择图片'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _originalFile != null ? _onCompress : null,
                      icon: const Icon(Icons.compress),
                      label: const Text('压缩到目标'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                textDirection: dir,
                children: [
                  Expanded(
                    child: _TargetSizeField(
                      value: _targetKB,
                      onChanged: (v) => setState(() => _targetKB = v),
                      label: '目标大小 (KB)',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Directionality(
                      textDirection: dir,
                      child: SwitchListTile(
                        contentPadding: EdgeInsetsDirectional.zero,
                        title: const Text('展示/上传原图'),
                        value: _includeOriginal,
                        onChanged: (v) => setState(() => _includeOriginal = v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_originalFile != null)
                _buildPreviewCard(context, file: _originalFile!, bytes: _originalBytes, title: '原图'),
              const SizedBox(height: 12),
              if (_compressedFile != null)
                _buildPreviewCard(
                  context,
                  file: _compressedFile!,
                  bytes: _compressedBytes,
                  title: '压缩图 (质量 $_qualityUsed)',
                ),
              if (_compressedFile != null) ...[const SizedBox(height: 12), _buildStatsCard(context)],
              const SizedBox(height: 20),
              Row(
                textDirection: dir,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: !_uploading && _originalFile != null ? () => _onUpload(original: true) : null,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('上传原图'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: !_uploading && _compressedFile != null ? () => _onUpload(original: false) : null,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('上传压缩图'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context, {required File file, int? bytes, required String title}) {
    final int size = bytes ?? file.lengthSync();
    final double kb = size / 1024.0;
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title  •  ${kb.toStringAsFixed(1)} KB'),
            const SizedBox(height: 8),
            Image.file(file, height: 220, fit: BoxFit.contain),
          ],
        ),
      ),
    );
  }

  Future<void> _onPick() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final File f = File(picked.path);
    final int b = await f.length();
    setState(() {
      _originalFile = f;
      _originalBytes = b;
      _compressedFile = null;
      _compressedBytes = null;
      _qualityUsed = null;
      _compressDurationMs = null;
    });
  }

  Future<void> _onCompress() async {
    if (_originalFile == null) return;
    final opts = ImageCompressorOptions(
      targetSizeInKB: _targetKB,
      initialQuality: 92,
      minQuality: 40,
      step: 4,
      maxWidth: 3000,
      maxHeight: 3000,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    final Stopwatch sw = Stopwatch()..start();
    final res = await ImageCompressorService.compressToTarget(_originalFile!, options: opts);
    sw.stop();
    setState(() {
      _compressedFile = res.file;
      _compressedBytes = res.bytes;
      _qualityUsed = res.qualityUsed;
      _compressDurationMs = sw.elapsedMilliseconds;
    });
  }

  Widget _buildStatsCard(BuildContext context) {
    final TextDirection dir = Directionality.of(context);
    final int? o = _originalBytes ?? _originalFile?.lengthSync();
    final int? c = _compressedBytes ?? _compressedFile?.lengthSync();
    final double? okb = o != null ? o / 1024.0 : null;
    final double? ckb = c != null ? c / 1024.0 : null;
    final String durationText = _compressDurationMs == null ? '-' : '$_compressDurationMs ms';

    String ratioText = '-';
    if (o != null && c != null && o > 0) {
      final double ratio = c / o;
      ratioText = '${(ratio * 100).toStringAsFixed(1)}%';
    }

    String savedText = '-';
    if (o != null && c != null) {
      final int saved = o - c;
      final double savedKb = saved / 1024.0;
      savedText = '${savedKb.toStringAsFixed(1)} KB';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              textDirection: dir,
              children: <Widget>[
                const Icon(Icons.image, size: 18),
                const SizedBox(width: 8),
                Text('原图大小: ${okb == null ? '-' : '${okb.toStringAsFixed(1)} KB'}'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              textDirection: dir,
              children: <Widget>[
                const Icon(Icons.compress, size: 18),
                const SizedBox(width: 8),
                Text('压缩后大小: ${ckb == null ? '-' : '${ckb.toStringAsFixed(1)} KB'}'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              textDirection: dir,
              children: const <Widget>[
                Icon(Icons.percent, size: 18),
                SizedBox(width: 8),
                // Placeholder; replaced by the next Text using ratioText via interpolation below
              ],
            ),
            // Using separate Text to ensure correct formatting and avoid const issues
            Padding(padding: const EdgeInsetsDirectional.fromSTEB(26, 0, 0, 0), child: Text('压缩比例: $ratioText')),
            const SizedBox(height: 6),
            Row(
              textDirection: dir,
              children: <Widget>[
                const Icon(Icons.timer, size: 18),
                const SizedBox(width: 8),
                Text('压缩耗时: $durationText'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              textDirection: dir,
              children: <Widget>[
                const Icon(Icons.savings, size: 18),
                const SizedBox(width: 8),
                Text('节省容量: $savedText'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onUpload({required bool original}) async {
    final File? file = original ? _originalFile : _compressedFile;
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      // Replace with your server url
      final Uri url = Uri.parse('https://httpbin.org/post');
      await _uploader.uploadFile(url: url, file: file, extraFields: {'original': original.toString()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上传成功')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
}

class _TargetSizeField extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final String label;
  const _TargetSizeField({required this.value, required this.onChanged, required this.label});

  @override
  State<_TargetSizeField> createState() => _TargetSizeFieldState();
}

class _TargetSizeFieldState extends State<_TargetSizeField> {
  late final TextEditingController _controller;
  bool _programmaticUpdate = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _controller.addListener(_onTextChanged);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TargetSizeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String currentText = _controller.text;
    final String newText = widget.value.toString();
    // Only sync from outside when not focused, to avoid overriding user typing
    if (!_focusNode.hasFocus && currentText != newText) {
      _programmaticUpdate = true;
      _controller.value = _controller.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
        composing: TextRange.empty,
      );
      _programmaticUpdate = false;
    }
  }

  void _onTextChanged() {
    if (_programmaticUpdate) return;
    final String text = _controller.text;
    final int? v = int.tryParse(text);
    if (v != null && v > 0) {
      widget.onChanged(v);
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) return;
    // On blur: commit valid value or restore to last good external value
    final String text = _controller.text;
    final int? v = int.tryParse(text);
    if (v != null && v > 0) {
      widget.onChanged(v);
    } else {
      final String fallback = widget.value.toString();
      _programmaticUpdate = true;
      _controller.value = _controller.value.copyWith(
        text: fallback,
        selection: TextSelection.collapsed(offset: fallback.length),
        composing: TextRange.empty,
      );
      _programmaticUpdate = false;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.tune),
        contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
    );
  }
}
