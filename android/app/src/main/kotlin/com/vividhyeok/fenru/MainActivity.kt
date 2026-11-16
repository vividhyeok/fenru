package com.vividhyeok.fenru

import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var stylusInContact = false

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (event.getToolType(event.actionIndex) == MotionEvent.TOOL_TYPE_STYLUS) {
                    stylusInContact = true
                }
            }
            MotionEvent.ACTION_POINTER_UP -> {
                if (event.getToolType(event.actionIndex) == MotionEvent.TOOL_TYPE_STYLUS) {
                    stylusInContact = false
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> stylusInContact = false
        }
        return super.dispatchTouchEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        val buttonChange = event.actionMasked == MotionEvent.ACTION_BUTTON_PRESS ||
            event.actionMasked == MotionEvent.ACTION_BUTTON_RELEASE
        val stylusButtons = MotionEvent.BUTTON_STYLUS_PRIMARY or MotionEvent.BUTTON_STYLUS_SECONDARY
        if (!stylusInContact || !buttonChange ||
            event.getToolType(event.actionIndex) != MotionEvent.TOOL_TYPE_STYLUS ||
            (event.actionButton and stylusButtons) == 0
        ) {
            return super.dispatchGenericMotionEvent(event)
        }

        // Flutter's Android embedding forwards button state on moves.
        val move = MotionEvent.obtainNoHistory(event)
        return try {
            move.action = MotionEvent.ACTION_MOVE
            super.dispatchTouchEvent(move)
        } finally {
            move.recycle()
        }
    }
}
