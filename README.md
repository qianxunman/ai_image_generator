# AI Image Generator

AI Image Generator 是一个基于 Flutter Windows 的 AI 图片生成客户端，支持 OpenAI 兼容的图片生成接口。

## 功能特性

- 输入提示词生成图片
- 支持 `b64_json` 和图片 URL 两种 API 返回格式
- 支持自定义 OpenAI 兼容 `Base URL`
- 支持 API Key 输入、显示/隐藏和可选本地保存
- 自动记住上一次使用的 `Base URL`
- 通过 `/models` 加载模型列表
- 支持模型搜索和选择，也支持手动输入模型名称
- 支持 `1024x1024`、`1024x1536`、`1536x1024` 图片尺寸
- 图片预览、缩放、清除和下载
- 自动读取 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量

## 使用要求

- Windows 10 或更高版本
- 可访问目标 API 服务的网络环境
- 一个 OpenAI 兼容的图片生成接口及 API Key
- 接口需要支持以下请求：
  - `GET /models`
  - `POST /images/generations`

## 快速使用

1. 启动 `flutter_image_generator.exe`。
2. 在 `Base URL` 中输入接口地址，例如：

   ```text
   https://api.example.com/v1
   ```

3. 输入 API Key。
4. 点击模型输入框右侧的搜索按钮加载模型列表。
5. 在模型选择窗口中搜索并选择模型，或者直接手动输入模型名称。
6. 选择图片尺寸并填写提示词。
7. 点击“生成图片”。
8. 生成完成后可以预览图片或点击“下载图片”保存。

## API 接口格式

### 获取模型列表

```http
GET /v1/models
Authorization: Bearer YOUR_API_KEY
```

客户端读取返回 JSON 中的 `data[].id` 作为模型名称。示例：

```json
{
  "data": [
    { "id": "grok-imagine-image" },
    { "id": "dall-e-3" }
  ]
}
```

### 生成图片

```http
POST /v1/images/generations
Authorization: Bearer YOUR_API_KEY
Content-Type: application/json
```

请求体：

```json
{
  "model": "grok-imagine-image",
  "prompt": "A cozy cabin under snowy mountains",
  "size": "1024x1024",
  "n": 1
}
```

客户端支持以下返回形式之一：

```json
{
  "data": [
    { "b64_json": "BASE64_IMAGE_DATA" }
  ]
}
```

或：

```json
{
  "data": [
    { "url": "https://example.com/generated-image.png" }
  ]
}
```

## API Key 和 Base URL 保存

- API Key 默认只保存在当前运行实例中。
- 勾选“保存 API Key 到本机”后，API Key 会保存到当前 Windows 用户目录。
- 下次启动时会自动恢复已保存的 API Key。
- 取消勾选或点击“清除”会删除已保存的 API Key。
- `Base URL` 会自动保存，并在下次启动时恢复。
- 本地配置文件名为 `image_studio_settings.json`，位置为：

  ```text
  %APPDATA%\image_studio_settings.json
  ```

API Key 是以本地配置文件形式保存的，不建议在共享电脑上启用保存功能。

## 代理配置

Windows 客户端会读取以下环境变量：

```powershell
$env:HTTP_PROXY = "http://127.0.0.1:7890"
$env:HTTPS_PROXY = "http://127.0.0.1:7890"
```

设置环境变量后，从同一个终端启动程序即可使用代理。若网络仍然失败，请检查：

- `Base URL` 是否包含正确的协议和路径
- 代理地址和端口是否可用
- Windows 防火墙是否允许程序联网
- API 服务是否支持当前接口路径

## 开发环境

当前项目使用 Flutter Windows 桌面端。安装 Flutter 后执行：

```powershell
flutter pub get
flutter analyze
flutter run -d windows
```

构建 Windows Release：

```powershell
flutter build windows --release
```

构建产物位于：

```text
build\windows\x64\runner\Release\
```

发布时需要复制整个 `Release` 目录，不能只复制 `.exe` 文件，因为程序还依赖同目录下的 DLL 文件和 `data` 目录。

## Windows 编译工具链

Windows 构建需要 Visual Studio 2022 Build Tools 或完整 Visual Studio，并安装：

- Desktop development with C++
- Windows 10 或 Windows 11 SDK

可以使用以下命令检查环境：

```powershell
flutter doctor -v
```

## 项目结构

```text
lib/main.dart                 应用界面、API 请求和本地配置逻辑
windows/                      Windows runner 和 CMake 配置
build/windows/x64/runner/    Windows 构建产物
pubspec.yaml                  Flutter 项目和依赖配置
```

## 注意事项

- 本项目只负责调用兼容接口，不提供图片生成服务。
- API Key、模型名称和接口路径由服务提供方决定。
- 不同服务商对模型、尺寸和返回格式的支持可能不同。
- 长时间生成请求最多等待 180 秒，模型列表请求最多等待 30 秒。
