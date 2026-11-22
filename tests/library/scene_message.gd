extends Node

var topics := ["🌲".repeat(64), "scene.温度", "scene.温度", "🌲".repeat(64), "done"]
var values := [-2147483648, 0, 0, 2147483647, -1]
var received := 0

func on_javafx_message(topic: String, value: int) -> void:
	if not Thread.is_main_thread() or received >= topics.size() or topic != topics[received] or value != values[received]:
		push_error("Unexpected scene message #%d: topic=%s value=%d main_thread=%s" % [received, topic, value, Thread.is_main_thread()])
		get_window().propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
		return
	received += 1
	if received == topics.size():
		print("SCENE_MESSAGE_FIFO_PASS count=", received)
		get_window().propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
