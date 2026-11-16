package com.vividhyeok.fenru

import android.accounts.Account
import android.accounts.AccountManager
import android.content.Intent
import android.view.MotionEvent
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.Scope
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val driveScope = "https://www.googleapis.com/auth/drive.appdata"
    private val driveRequestCode = 4187
    private val driveAccountRequestCode = 4188
    private var driveResult: MethodChannel.Result? = null
    private var selectedDriveAccount: String? = null
    private val drivePreferences by lazy { getSharedPreferences("fenru_drive", MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fenru/drive")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "authorize", "connect" -> startDriveAuthorization(
                        call.method == "connect", call.arguments == true, result
                    )
                    "disconnect" -> {
                        drivePreferences.edit().remove("account").apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startDriveAuthorization(
        selectAccount: Boolean, interactive: Boolean, result: MethodChannel.Result
    ) {
        if (driveResult != null) {
            result.error("busy", "Google 연결이 이미 진행 중입니다.", null)
            return
        }
        driveResult = result
        if (selectAccount) {
            try {
                val chooser = AccountManager.newChooseAccountIntent(
                    null, null, arrayOf("com.google"), null, null, null, null
                )
                startActivityForResult(chooser, driveAccountRequestCode)
            } catch (e: android.content.ActivityNotFoundException) {
                finishDrive(null)
            }
        } else {
            selectedDriveAccount = drivePreferences.getString("account", null)
            authorizeDrive(interactive)
        }
    }

    private fun authorizeDrive(interactive: Boolean) {
        val builder = AuthorizationRequest.builder()
            .setRequestedScopes(listOf(Scope(driveScope)))
        selectedDriveAccount?.let { builder.setAccount(Account(it, "com.google")) }
        Identity.getAuthorizationClient(this).authorize(builder.build())
            .addOnSuccessListener { authorization ->
                val pending = authorization.pendingIntent
                if (pending == null) {
                    finishDrive(authorization)
                } else if (!interactive) {
                    finishDrive(null)
                } else {
                    try {
                        startIntentSenderForResult(pending.intentSender, driveRequestCode, null, 0, 0, 0)
                    } catch (e: android.content.IntentSender.SendIntentException) {
                        finishDrive(null)
                    }
                }
            }
            .addOnFailureListener { error ->
                val reason = (error as? ApiException)?.statusCode?.let { " ($it)" } ?: ""
                driveResult?.error("authorization", "Google Drive 연결에 실패했습니다$reason.", null)
                driveResult = null
                selectedDriveAccount = null
            }
    }

    private fun finishDrive(authorization: AuthorizationResult?) {
        val allowed = authorization?.grantedScopes?.contains(driveScope) == true
        val token = if (allowed) authorization?.accessToken else null
        if (token != null) {
            selectedDriveAccount?.let { drivePreferences.edit().putString("account", it).apply() }
        }
        driveResult?.success(token)
        driveResult = null
        selectedDriveAccount = null
    }

    @Deprecated("Used for the Google authorization resolution in FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == driveAccountRequestCode) {
            val account = data?.getStringExtra(AccountManager.KEY_ACCOUNT_NAME)
            if (resultCode != RESULT_OK || account.isNullOrEmpty()) {
                finishDrive(null)
            } else {
                selectedDriveAccount = account
                authorizeDrive(true)
            }
            return
        }
        if (requestCode != driveRequestCode) return
        if (resultCode != RESULT_OK) {
            finishDrive(null)
            return
        }
        try {
            finishDrive(Identity.getAuthorizationClient(this).getAuthorizationResultFromIntent(data))
        } catch (e: ApiException) {
            finishDrive(null)
        }
    }

    private var stylusContact: MotionEvent? = null
    private var stylusPointerId: Int? = null
    private var buttonDeviceId: Int? = null
    private var heldButtons = 0
    private var touchReportedButton = false

    private fun stylusButtons(buttons: Int): Int {
        val mask = MotionEvent.BUTTON_STYLUS_PRIMARY or MotionEvent.BUTTON_STYLUS_SECONDARY
        val explicit = buttons and mask
        if (explicit != 0) return explicit
        // A stylus driver can expose the barrel button as BUTTON_SECONDARY.
        return if ((buttons and MotionEvent.BUTTON_SECONDARY) != 0) {
            MotionEvent.BUTTON_STYLUS_PRIMARY
        } else {
            0
        }
    }

    private fun clearStylusContact() {
        stylusContact?.recycle()
        stylusContact = null
        stylusPointerId = null
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        val index = event.actionIndex
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (event.actionMasked == MotionEvent.ACTION_DOWN) clearStylusContact()
                if (event.getToolType(index) == MotionEvent.TOOL_TYPE_STYLUS) {
                    stylusPointerId = event.getPointerId(index)
                }
            }
            MotionEvent.ACTION_POINTER_UP -> {
                if (event.getPointerId(index) == stylusPointerId) clearStylusContact()
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> clearStylusContact()
        }
        val pointerId = stylusPointerId ?: return super.dispatchTouchEvent(event)
        if (event.findPointerIndex(pointerId) < 0) return super.dispatchTouchEvent(event)
        // Refresh the contact snapshot on movement and pointer-set changes.
        stylusContact?.recycle()
        stylusContact = MotionEvent.obtainNoHistory(event)

        val fromTouch = stylusButtons(event.buttonState)
        if (event.deviceId == buttonDeviceId) {
            if (fromTouch != 0) touchReportedButton = true
            if (fromTouch == 0 && touchReportedButton &&
                event.actionMasked == MotionEvent.ACTION_MOVE
            ) heldButtons = 0
        }
        val buttons = fromTouch or (if (event.deviceId == buttonDeviceId) heldButtons else 0)
        if ((buttons and event.buttonState) == buttons) return super.dispatchTouchEvent(event)
        return dispatchStylusEvent(event, event.action, event.eventTime, event.buttonState or buttons)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        val contact = stylusContact
        val action = event.actionMasked
        if (action != MotionEvent.ACTION_BUTTON_PRESS && action != MotionEvent.ACTION_BUTTON_RELEASE) {
            return super.dispatchGenericMotionEvent(event)
        }
        if (event.getToolType(event.actionIndex) != MotionEvent.TOOL_TYPE_STYLUS &&
            event.deviceId != contact?.deviceId &&
            event.deviceId != buttonDeviceId
        ) return super.dispatchGenericMotionEvent(event)
        val changed = stylusButtons(event.actionButton)
        if (changed == 0) return super.dispatchGenericMotionEvent(event)
        val state = stylusButtons(event.buttonState)
        val buttons = if (action == MotionEvent.ACTION_BUTTON_PRESS) {
            state or changed
        } else {
            state and changed.inv()
        }
        buttonDeviceId = event.deviceId
        heldButtons = buttons
        touchReportedButton = false
        val pointerId = stylusPointerId
        if (contact == null || pointerId == null || event.deviceId != contact.deviceId) {
            return super.dispatchGenericMotionEvent(event)
        }

        // Generic events can have different pointer IDs from the touch stream.
        // Keep the current contact's IDs and coordinates when delivering the change.
        return dispatchStylusEvent(
            contact, MotionEvent.ACTION_MOVE, event.eventTime, buttons,
            intArrayOf(contact.findPointerIndex(pointerId))
        )
    }

    private fun dispatchStylusEvent(
        source: MotionEvent,
        action: Int,
        eventTime: Long,
        buttons: Int,
        indices: IntArray = IntArray(source.pointerCount) { it }
    ): Boolean {
        val properties = Array(indices.size) { index ->
            MotionEvent.PointerProperties().also { source.getPointerProperties(indices[index], it) }
        }
        val coords = Array(indices.size) { index ->
            MotionEvent.PointerCoords().also { source.getPointerCoords(indices[index], it) }
        }
        val normalized = MotionEvent.obtain(
            source.downTime, eventTime, action, indices.size,
            properties, coords, source.metaState, buttons,
            source.xPrecision, source.yPrecision, source.deviceId,
            source.edgeFlags, source.source, source.flags
        )
        return try {
            super.dispatchTouchEvent(normalized)
        } finally {
            normalized.recycle()
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        if (!hasFocus) {
            clearStylusContact()
            buttonDeviceId = null
            heldButtons = 0
            touchReportedButton = false
        }
        super.onWindowFocusChanged(hasFocus)
    }
}
