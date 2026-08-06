import 'package:mova/mova.dart';

/// Builds the [MovaSttModelSpec] for the bilingual Zipformer
/// (`zipformer-zh-en-2023-11-22`) [ZipformerSttEngine] expects.
///
/// [baseUrl] must point at a host serving the four files **already
/// extracted** from sherpa-onnx's official `.tar.bz2` release — see
/// `mova/doc/notes/2026-08-04-stt-engine-decision.md`: the official
/// GitHub Releases asset is a compressed archive, and this package does not
/// decompress on-device, so [baseUrl] cannot point at
/// `k2-fsa/sherpa-onnx`'s release directly. The placeholder default is not a
/// real, working URL — replace it with wherever the four files actually get
/// re-hosted.
///
/// 构建 [ZipformerSttEngine] 所需的中英双语 Zipformer
/// （`zipformer-zh-en-2023-11-22`）的 [MovaSttModelSpec]。
///
/// [baseUrl] 必须指向一个已经把 sherpa-onnx 官方 `.tar.bz2` 发布包**解压好**
/// 的四个文件的托管地址——见
/// `mova/doc/notes/2026-08-04-stt-engine-decision.md`：官方 GitHub
/// Releases 资产是压缩包，本包不做端上解压，因此 [baseUrl] 不能直接指向
/// `k2-fsa/sherpa-onnx` 的官方 Release。默认的占位值不是一个真实可用的
/// URL——需要替换成四个文件实际重新托管的地址。
///
/// - [baseUrl]: directory URL the four files are served under, no trailing
///   slash / 四个文件所在目录的 URL，末尾不带斜杠
///
/// Returns the model spec.
///
/// 返回模型描述。
MovaSttModelSpec zipformerZhEnModelSpec({
  String baseUrl = 'https://REPLACE-ME.example.com/zipformer-zh-en-2023-11-22',
}) {
  return MovaSttModelSpec(
    id: 'zipformer-zh-en-2023-11-22',
    files: [
      MovaSttModelFile(
        name: 'encoder.onnx',
        url: Uri.parse('$baseUrl/encoder-epoch-34-avg-19.int8.onnx'),
      ),
      MovaSttModelFile(
        name: 'decoder.onnx',
        url: Uri.parse('$baseUrl/decoder-epoch-34-avg-19.onnx'),
      ),
      MovaSttModelFile(
        name: 'joiner.onnx',
        url: Uri.parse('$baseUrl/joiner-epoch-34-avg-19.int8.onnx'),
      ),
      MovaSttModelFile(
        name: 'tokens.txt',
        url: Uri.parse('$baseUrl/tokens.txt'),
      ),
    ],
  );
}
