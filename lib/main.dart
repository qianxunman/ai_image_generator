import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/io_client.dart';

const _defaultBaseUrl = 'https://api.a6api.com/v1';
const _defaultModel = 'grok-imagine-image';
const _settingsFileName = 'image_studio_settings.json';

void main() => runApp(const ImageStudioApp());

class ImageStudioApp extends StatelessWidget {
  const ImageStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0D1117);
    const surface = Color(0xFF161B22);
    const primary = Color(0xFF8B9CFF);
    return MaterialApp(
      title: 'AI Image Generator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.dark,
          surface: surface,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF30363D)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF30363D)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF30363D)),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const ImageStudioPage(),
    );
  }
}

class ImageStudioPage extends StatefulWidget {
  const ImageStudioPage({super.key});

  @override
  State<ImageStudioPage> createState() => _ImageStudioPageState();
}

class _ImageStudioPageState extends State<ImageStudioPage> {
  final _promptController = TextEditingController();
  final _baseUrlController = TextEditingController(text: _defaultBaseUrl);
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController(text: _defaultModel);

  Uint8List? _imageBytes;
  String? _imageExtension;
  String? _errorMessage;
  bool _isGenerating = false;
  bool _obscureKey = true;
  bool _saveApiKey = false;
  bool _isEnglish = false;
  bool _isLoadingModels = false;
  List<String> _models = const [];
  String _size = '1024x1024';

  String _tr(String chinese, String english) => _isEnglish ? english : chinese;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedSettings());
  }

  @override
  void dispose() {
    _promptController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final prompt = _promptController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();

    if (prompt.isEmpty) return _showError('请输入图片提示词');
    if (apiKey.isEmpty) return _showError('请输入 API Key');
    if (baseUrl.isEmpty) return _showError('请输入 Base URL');
    if (model.isEmpty) return _showError('请输入模型名称');

    await _saveBaseUrlToDisk(baseUrl);
    if (_saveApiKey) {
      await _saveApiKeyToDisk(apiKey);
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    final client = _createHttpClient();
    try {
      final endpoint = Uri.parse(
        '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/images/generations',
      );
      final response = await client
          .post(
            endpoint,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'prompt': prompt,
              'size': _size,
              'n': 1,
            }),
          )
          .timeout(const Duration(seconds: 180));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'API 请求失败（HTTP ${response.statusCode}）：${_responseMessage(response.body)}',
        );
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) throw Exception('API 返回格式无效');
      final items = payload['data'];
      if (items is! List || items.isEmpty || items.first is! Map) {
        throw Exception('API 返回中没有图片数据：${response.body}');
      }

      final image = Map<String, dynamic>.from(items.first as Map);
      late Uint8List bytes;
      late String extension;
      final base64Image = image['b64_json'];
      if (base64Image is String && base64Image.isNotEmpty) {
        bytes = base64Decode(base64Image);
        extension = 'png';
      } else if (image['url'] is String &&
          (image['url'] as String).isNotEmpty) {
        final imageResponse = await client
            .get(Uri.parse(image['url'] as String))
            .timeout(const Duration(seconds: 180));
        if (imageResponse.statusCode < 200 || imageResponse.statusCode >= 300) {
          throw Exception('图片下载失败（HTTP ${imageResponse.statusCode}）');
        }
        bytes = imageResponse.bodyBytes;
        extension = _extensionFromContentType(
          imageResponse.headers['content-type'],
        );
      } else {
        throw Exception('API 返回中既没有 b64_json，也没有 url');
      }

      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageExtension = extension;
      });
      _showMessage('图片生成成功');
    } on FormatException {
      _showError('API 返回的图片数据不是有效的 Base64 或 JSON');
    } on SocketException catch (error) {
      _showError('网络请求失败：${error.message}（请检查 Base URL、代理和防火墙）');
    } on TimeoutException {
      _showError('请求超时，请检查网络或服务端状态');
    } catch (error) {
      _showError(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      client.close();
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  IOClient _createHttpClient() {
    final httpClient = HttpClient()
      // Dart does not automatically apply HTTP_PROXY/HTTPS_PROXY to requests.
      ..findProxy = HttpClient.findProxyFromEnvironment;
    return IOClient(httpClient);
  }

  File get _settingsFile => File(
    '${Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? '.'}\\$_settingsFileName',
  );

  Future<void> _loadSavedSettings() async {
    try {
      final file = _settingsFile;
      if (!await file.exists()) return;
      final settings = jsonDecode(await file.readAsString());
      if (settings is! Map) return;
      final baseUrl = settings['baseUrl'];
      final apiKey = settings['apiKey'];
      if (baseUrl is String && baseUrl.trim().isNotEmpty) {
        _baseUrlController.text = baseUrl.trim();
      }
      if (apiKey is String && apiKey.trim().isNotEmpty && mounted) {
        _apiKeyController.text = apiKey.trim();
        setState(() => _saveApiKey = true);
        unawaited(_loadModels(showError: false));
      }
    } catch (_) {
      // Ignore unreadable optional settings and allow manual entry.
    }
  }

  Future<void> _setSaveApiKey(bool value) async {
    setState(() => _saveApiKey = value);
    if (!value) {
      try {
        final file = _settingsFile;
        if (await file.exists()) {
          final content = jsonDecode(await file.readAsString());
          final settings = content is Map
              ? Map<String, dynamic>.from(content)
              : <String, dynamic>{};
          settings.remove('apiKey');
          if (settings.isEmpty) {
            await file.delete();
          } else {
            await file.writeAsString(jsonEncode(settings), flush: true);
          }
        }
      } catch (_) {
        _showError('清除已保存 API Key 失败');
      }
      return;
    }

    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isNotEmpty) await _saveApiKeyToDisk(apiKey);
  }

  Future<void> _saveApiKeyToDisk(String apiKey) async {
    try {
      final settings = await _readSettings();
      settings['apiKey'] = apiKey;
      await _writeSettings(settings);
    } catch (_) {
      if (mounted) _showError('保存 API Key 失败，请检查用户目录权限');
    }
  }

  Future<void> _saveBaseUrlToDisk(String baseUrl) async {
    if (baseUrl.isEmpty) return;
    try {
      final settings = await _readSettings();
      settings['baseUrl'] = baseUrl;
      await _writeSettings(settings);
    } catch (_) {
      if (mounted) _showError('保存 Base URL 失败，请检查用户目录权限');
    }
  }

  Future<Map<String, dynamic>> _readSettings() async {
    final file = _settingsFile;
    if (!await file.exists()) return <String, dynamic>{};
    final content = jsonDecode(await file.readAsString());
    return content is Map
        ? Map<String, dynamic>.from(content)
        : <String, dynamic>{};
  }

  Future<void> _writeSettings(Map<String, dynamic> settings) async {
    await _settingsFile.writeAsString(jsonEncode(settings), flush: true);
  }

  Future<void> _loadModels({bool showError = true}) async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (baseUrl.isEmpty) {
      if (showError) _showError('请先输入 Base URL');
      return;
    }
    if (apiKey.isEmpty) {
      if (showError) _showError('请先输入 API Key');
      return;
    }

    setState(() => _isLoadingModels = true);
    final client = _createHttpClient();
    try {
      final endpoint = Uri.parse(
        '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/models',
      );
      final response = await client
          .get(
            endpoint,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          '模型列表请求失败（HTTP ${response.statusCode}）：${_responseMessage(response.body)}',
        );
      }

      final payload = jsonDecode(response.body);
      final data = payload is Map ? payload['data'] : null;
      if (data is! List) throw Exception('模型列表返回格式无效');
      final models =
          data
              .whereType<Map>()
              .map((item) => item['id'])
              .whereType<String>()
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (!mounted) return;
      setState(() => _models = models);
      if (showError) {
        _showMessage('已加载 ${models.length} 个模型');
        await _showModelPicker();
      }
    } on SocketException catch (error) {
      if (showError) _showError('模型列表加载失败：${error.message}');
    } on TimeoutException {
      if (showError) _showError('模型列表加载超时，请检查网络或服务端状态');
    } catch (error) {
      if (showError) {
        _showError(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      client.close();
      if (mounted) setState(() => _isLoadingModels = false);
    }
  }

  Future<void> _showModelPicker() async {
    if (_models.isEmpty || !mounted) return;
    final searchController = TextEditingController();
    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final keyword = searchController.text.trim().toLowerCase();
            final filtered = _models
                .where((model) => model.toLowerCase().contains(keyword))
                .toList();
            return AlertDialog(
              title: Text(_tr('选择模型', 'Select model')),
              content: SizedBox(
                width: 520,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: _tr('搜索模型名称', 'Search models'),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(_tr('没有匹配的模型', 'No matching models')),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final model = filtered[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.memory_outlined),
                                  title: Text(model),
                                  selected: model == _modelController.text,
                                  onTap: () => Navigator.of(context).pop(model),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(_tr('取消', 'Cancel')),
                ),
              ],
            );
          },
        );
      },
    );
    searchController.dispose();
    if (selected != null && mounted) {
      setState(() => _modelController.text = selected);
    }
  }

  Future<void> _download() async {
    final bytes = _imageBytes;
    if (bytes == null) return;
    final extension = _imageExtension ?? 'png';
    final location = await getSaveLocation(
      suggestedName: 'generated_${_timestamp()}.$extension',
    );
    if (location == null) return;
    try {
      await File(location.path).writeAsBytes(bytes, flush: true);
      if (mounted) _showMessage('图片已保存到：${location.path}');
    } catch (error) {
      if (mounted) _showError('保存图片失败：$error');
    }
  }

  void _clearImage() {
    setState(() {
      _imageBytes = null;
      _imageExtension = null;
      _errorMessage = null;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade800),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _responseMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        if (error['message'] is String) return error['message'] as String;
      }
    } catch (_) {
      // Use the raw body when the server did not return JSON.
    }
    return body.length > 500 ? '${body.substring(0, 500)}…' : body;
  }

  String _extensionFromContentType(String? contentType) {
    if (contentType?.contains('jpeg') == true ||
        contentType?.contains('jpg') == true) {
      return 'jpg';
    }
    if (contentType?.contains('webp') == true) return 'webp';
    return 'png';
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 18 : 42,
                vertical: compact ? 18 : 28,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 26),
                      if (compact)
                        Column(
                          children: [
                            _buildSettingsCard(),
                            const SizedBox(height: 18),
                            _buildPreviewCard(),
                          ],
                        )
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 340, child: _buildSettingsCard()),
                            const SizedBox(width: 18),
                            Expanded(child: _buildPreviewCard()),
                          ],
                        ),
                      const SizedBox(height: 20),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8B9CFF), Color(0xFFB889FF)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.auto_awesome, color: Color(0xFF10131D)),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI Image Generator',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 3),
            Text(
              _tr(
                'OpenAI 兼容的 AI 图片生成器',
                'OpenAI-compatible AI image generator',
              ),
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
            ),
          ],
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () => setState(() => _isEnglish = !_isEnglish),
          icon: const Icon(Icons.language, size: 17),
          label: Text(_isEnglish ? '中文' : 'English'),
        ),
      ],
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.tune, _tr('生成设置', 'Generation settings')),
            const SizedBox(height: 14),
            _fieldLabel('Base URL', required: true),
            const SizedBox(height: 8),
            TextField(
              controller: _baseUrlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.link, size: 19),
                hintText: 'https://api.example.com/v1',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.key_outlined, size: 19),
                      suffixIcon: IconButton(
                        tooltip: _obscureKey
                            ? _tr('显示 Key', 'Show key')
                            : _tr('隐藏 Key', 'Hide key'),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 19,
                        ),
                      ),
                      hintText: 'API Key',
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Checkbox(
                  value: _saveApiKey,
                  onChanged: _isGenerating
                      ? null
                      : (value) => _setSaveApiKey(value ?? false),
                ),
                Text(_tr('记住', 'Remember')),
                if (_saveApiKey)
                  TextButton(
                    onPressed: _isGenerating
                        ? null
                        : () {
                            _apiKeyController.clear();
                            _setSaveApiKey(false);
                          },
                    child: Text(_tr('清除', 'Clear')),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _fieldLabel(_tr('模型', 'Model'), required: true),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _modelController,
                    decoration: const InputDecoration(
                      hintText: 'grok-imagine-image',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: _tr('加载模型列表并搜索', 'Load and search models'),
                  onPressed: _isLoadingModels ? null : () => _loadModels(),
                  icon: _isLoadingModels
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
              ],
            ),
            if (_models.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                _tr(
                  '已加载 ${_models.length} 个模型，点击右侧按钮搜索选择',
                  '${_models.length} models loaded. Click the button to search',
                ),
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
              ),
            ],
            const SizedBox(height: 10),
            _fieldLabel(_tr('尺寸', 'Size')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _size,
              items: const [
                DropdownMenuItem(
                  value: '1024x1024',
                  child: Text('1024 × 1024'),
                ),
                DropdownMenuItem(
                  value: '1024x1536',
                  child: Text('1024 × 1536'),
                ),
                DropdownMenuItem(
                  value: '1536x1024',
                  child: Text('1536 × 1024'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _size = value);
              },
            ),
            const SizedBox(height: 18),
            _fieldLabel(_tr('提示词', 'Prompt'), required: true),
            const SizedBox(height: 8),
            TextField(
              controller: _promptController,
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: _tr(
                  '例如：一座雪山脚下的温馨木屋，电影感光影…',
                  'Example: a cozy cabin under snowy mountains, cinematic lighting...',
                ),
                alignLabelWithHint: true,
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3D1D26),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF7D3444)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFFFFB8C3),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: FilledButton.icon(
                onPressed: _isGenerating ? null : _generate,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 19),
                label: Text(
                  _isGenerating
                      ? _tr('生成中，请稍候…', 'Generating...')
                      : _tr('生成图片', 'Generate image'),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    final image = _imageBytes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _sectionTitle(
                    Icons.image_outlined,
                    _tr('图片预览', 'Image preview'),
                  ),
                ),
                if (image != null) ...[
                  TextButton.icon(
                    onPressed: _clearImage,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(_tr('清除', 'Clear')),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: _download,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(_tr('下载图片', 'Download image')),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: image == null
                  ? _emptyPreview()
                  : Container(
                      key: const ValueKey('image'),
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 520),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4,
                        child: Image.memory(
                          image,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Text(_tr('图片预览失败', 'Preview failed')),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyPreview() {
    return Container(
      key: const ValueKey('empty'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 520),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_size_select_actual_outlined,
            size: 58,
            color: Color(0xFF484F58),
          ),
          SizedBox(height: 16),
          Text(
            _tr('生成的图片会显示在这里', 'Generated images will appear here'),
            style: TextStyle(color: Color(0xFF8B949E), fontSize: 15),
          ),
          SizedBox(height: 7),
          Text(
            _tr(
              '输入提示词并点击“生成图片”开始创作',
              'Enter a prompt and click "Generate image" to start',
            ),
            style: TextStyle(color: Color(0xFF484F58), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      children: [
        const Icon(
          Icons.desktop_windows_outlined,
          size: 15,
          color: Color(0xFF6E7681),
        ),
        const SizedBox(width: 7),
        Text(
          _tr(
            'Windows 桌面端 · 支持 OpenAI 兼容图片接口',
            'Windows desktop · OpenAI-compatible image API',
          ),
          style: TextStyle(color: Color(0xFF6E7681), fontSize: 12),
        ),
      ],
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF9AA8FF)),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text, {bool required = false}) {
    return RichText(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 12, color: Color(0xFFC9D1D9)),
        children: required
            ? const [
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: Color(0xFFFF7B72)),
                ),
              ]
            : null,
      ),
    );
  }
}
