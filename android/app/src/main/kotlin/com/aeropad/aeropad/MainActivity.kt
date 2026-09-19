package com.aeropad.aeropad

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppQosSettings
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothProfile
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private lateinit var hid: HidController

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        hid = HidController(this)
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.aeropad/hid").setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> { hid.connect(); result.success(null) }
                "sendReport" -> {
                    hid.sendReport(
                        call.argument<Int>("buttons") ?: 0,
                        call.argument<Int>("dx") ?: 0,
                        call.argument<Int>("dy") ?: 0,
                        call.argument<Int>("wheel") ?: 0
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(engine.dartExecutor.binaryMessenger, "com.aeropad/hid_state").setStreamHandler(hid)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == HidController.PERMISSION_REQUEST && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) hid.connect()
    }
}

private class HidController(private val activity: MainActivity) : EventChannel.StreamHandler {
    companion object { const val PERMISSION_REQUEST = 4102 }
    private val adapter = BluetoothAdapter.getDefaultAdapter()
    private val executor = Executors.newSingleThreadExecutor()
    private var hid: BluetoothHidDevice? = null
    private var host: BluetoothDevice? = null
    private var sink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events; emit("disconnected") }
    override fun onCancel(arguments: Any?) { sink = null }

    private fun emit(value: String) { activity.runOnUiThread { sink?.success(value) } }

    @SuppressLint("MissingPermission")
    fun connect() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val needed = arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_SCAN)
            if (needed.any { ActivityCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED }) {
                ActivityCompat.requestPermissions(activity, needed, PERMISSION_REQUEST)
                return
            }
        }
        if (adapter == null || !adapter.isEnabled) return
        adapter.getProfileProxy(activity, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                hid = proxy as BluetoothHidDevice
                val descriptor = byteArrayOf(0x05, 0x01, 0x09, 0x02, 0xA1.toByte(), 0x01, 0x09, 0x01, 0xA1.toByte(), 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x03, 0x15, 0x00, 0x25, 0x01, 0x95.toByte(), 0x03, 0x75, 0x01, 0x81.toByte(), 0x02, 0x95.toByte(), 0x01, 0x75, 0x05, 0x81.toByte(), 0x01, 0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x38, 0x15, 0x81.toByte(), 0x25, 0x7F, 0x75, 0x08, 0x95.toByte(), 0x03, 0x81.toByte(), 0x06, 0xC0.toByte(), 0xC0.toByte())
                hid?.registerApp(
                    BluetoothHidDeviceAppSdpSettings("AeroPad", "AeroPad Bluetooth Mouse", "AeroPad", BluetoothHidDevice.SUBCLASS1_MOUSE, descriptor),
                    BluetoothHidDeviceAppQosSettings(BluetoothHidDeviceAppQosSettings.SERVICE_BEST_EFFORT, 800, 9, 0, 0, 0),
                    null, executor, callback
                )
            }
            override fun onServiceDisconnected(profile: Int) { hid = null; emit("disconnected") }
        }, BluetoothProfile.HID_DEVICE)
    }

    private val callback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(device: BluetoothDevice?, registered: Boolean) {
            if (device != null) host = device
            emit(if (registered) "discoverable" else "disconnected")
        }
        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            host = device
            emit(if (state == BluetoothProfile.STATE_CONNECTED) "connected" else if (state == BluetoothProfile.STATE_CONNECTING) "discoverable" else "disconnected")
        }
        override fun onGetReport(device: BluetoothDevice, type: Byte, id: Byte, bufferSize: Int) { hid?.replyReport(device, type, id, byteArrayOf(0, 0, 0, 0)) }
        override fun onSetReport(device: BluetoothDevice, type: Byte, id: Byte, data: ByteArray) = Unit
        override fun onSetProtocol(device: BluetoothDevice, protocol: Byte) = Unit
        override fun onInterruptData(device: BluetoothDevice, reportId: Byte, data: ByteArray) = Unit
    }

    @SuppressLint("MissingPermission")
    fun sendReport(buttons: Int, dx: Int, dy: Int, wheel: Int) {
        val device = host ?: return
        val data = byteArrayOf(buttons.coerceIn(0, 7).toByte(), dx.coerceIn(-127, 127).toByte(), dy.coerceIn(-127, 127).toByte(), wheel.coerceIn(-127, 127).toByte())
        hid?.sendReport(device, 0, data)
    }
}
