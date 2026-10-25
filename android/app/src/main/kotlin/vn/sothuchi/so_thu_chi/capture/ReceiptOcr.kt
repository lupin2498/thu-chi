package vn.sothuchi.so_thu_chi.capture

import android.content.Context
import android.net.Uri
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

/** Đọc chữ trên ảnh biên lai bằng ML Kit (chạy trên máy, không gửi ảnh đi đâu). */
object ReceiptOcr {
    fun recognize(ctx: Context, uri: Uri, callback: (List<ReceiptParser.Line>?) -> Unit) {
        try {
            val image = InputImage.fromFilePath(ctx, uri)
            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            recognizer.process(image)
                .addOnSuccessListener { text ->
                    val lines = ArrayList<ReceiptParser.Line>()
                    for (block in text.textBlocks) {
                        for (line in block.lines) {
                            val box = line.boundingBox
                            lines.add(
                                ReceiptParser.Line(
                                    text = line.text,
                                    height = box?.height() ?: 0,
                                    top = box?.top ?: 0,
                                    left = box?.left ?: 0,
                                )
                            )
                        }
                    }
                    recognizer.close()
                    callback(lines)
                }
                .addOnFailureListener { e ->
                    Log.w("SoThuChiCapture", "OCR lỗi", e)
                    recognizer.close()
                    callback(null)
                }
        } catch (e: Exception) {
            Log.w("SoThuChiCapture", "Không đọc được ảnh chia sẻ", e)
            callback(null)
        }
    }
}
