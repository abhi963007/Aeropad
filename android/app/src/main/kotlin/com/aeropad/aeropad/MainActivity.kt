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
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
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
                "makeDiscoverable" -> { hid.makeDiscoverable(); result.success(null) }
                "getBondedDevices" -> { result.success(hid.bondedDevices()) }
                "connectToDevice" -> {
                    val address = call.argument<String>("address")
                    if (address == null) result.error("INVALID_ADDRESS", "A Bluetooth address is required", null)
                    else { hid.connectToDevice(address); result.success(null) }
                }
                "disconnect" -> { hid.disconnect(); result.success(null) }
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        hid.onActivityResult(requestCode, resultCode)
    }
}

private class HidController(private val activity: MainActivity) : EventChannel.StreamHandler {
    companion object {
        const val PERMISSION_REQUEST = 4102
        const val ENABLE_REQUEST = 4103
        const val DISCOVERABLE_REQUEST = 4104
    }
    private val adapter = BluetoothAdapter.getDefaultAdapter()
    private val executor = Executors.newSingleThreadExecutor()
    private var hid: BluetoothHidDevice? = null
    private var host: BluetoothDevice? = null
    private var sink: EventChannel.EventSink? = null
    private var pendingAddress: String? = null
    private var pendingDiscoverable = false

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events; emit("disconnected") }
    override fun onCancel(arguments: Any?) { sink = null }

    private fun emit(state: String, name: String? = null) {
        activity.runOnUiThread {
            sink?.success(mapOf("state" to state, "name" to (name ?: "")))
        }
    }

    @SuppressLint("MissingPermission")
    fun connect() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val needed = arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_SCAN)
            if (needed.any { ActivityCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED }) {
                ActivityCompat.requestPermissions(activity, needed, PERMISSION_REQUEST)
                return
            }
        }
        if (adapter == null) return
        if (!adapter.isEnabled) {
            pendingDiscoverable = false
            activity.startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), ENABLE_REQUEST)
            return
        }
        adapter.getProfileProxy(activity, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                hid = proxy as BluetoothHidDevice
                val descriptor = byteArrayOf(0x05, 0x01, 0x09, 0x02, 0xA1.toByte(), 0x01, 0x09, 0x01, 0xA1.toByte(), 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x03, 0x15, 0x00, 0x25, 0x01, 0x95.toByte(), 0x03, 0x75, 0x01, 0x81.toByte(), 0x02, 0x95.toByte(), 0x01, 0x75, 0x05, 0x81.toByte(), 0x01, 0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x38, 0x15, 0x81.toByte(), 0x25, 0x7F, 0x75, 0x08, 0x95.toByte(), 0x03, 0x81.toByte(), 0x06, 0xC0.toByte(), 0xC0.toByte())
                hid?.registerApp(
                    BluetoothHidDeviceAppSdpSettings("AeroPad", "AeroPad Bluetooth Mouse", "AeroPad", BluetoothHidDevice.SUBCLASS1_MOUSE, descriptor),
                    BluetoothHidDeviceAppQosSettings(BluetoothHidDeviceAppQosSettings.SERVICE_BEST_EFFORT, 800, 9, 0, 0, 0),
                    null, executor, callback
                )
                hid?.let { onHidReady() }
            }
            override fun onServiceDisconnected(profile: Int) { hid = null; emit("disconnected") }
        }, BluetoothProfile.HID_DEVICE)
    }

    @SuppressLint("MissingPermission")
    fun makeDiscoverable() {
        if (adapter == null) return
        if (!adapter.isEnabled) {
            pendingDiscoverable = true
            activity.startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), ENABLE_REQUEST)
            return
        }
        activity.startActivityForResult(
            Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300),
            DISCOVERABLE_REQUEST
        )
        emit("discoverable")
        connect()
    }

    @SuppressLint("MissingPermission")
    fun bondedDevices(): List<Map<String, String>> {
        if (adapter == null || !adapter.isEnabled) return emptyList()
        return adapter.bondedDevices.map { device ->
            mapOf("name" to (device.name ?: "Unknown device"), "address" to device.address)
        }.sortedBy { it["name"] }
    }

    @SuppressLint("MissingPermission")
    fun connectToDevice(address: String) {
        if (adapter == null || !adapter.isEnabled) {
            pendingAddress = address
            connect()
            return
        }
        val device = adapter.getRemoteDevice(address)
        pendingAddress = address
        if (hid == null) connect()
        else hid?.connect(device)
    }

    @SuppressLint("MissingPermission")
    fun disconnect() {
        host?.let { hid?.disconnect(it) }
        host = null
        emit("disconnected")
    }

    fun onActivityResult(requestCode: Int, resultCode: Int) {
        if (requestCode == ENABLE_REQUEST && resultCode == android.app.Activity.RESULT_OK) {
            if (pendingDiscoverable) {
                pendingDiscoverable = false
                makeDiscoverable()
            } else {
                pendingAddress?.let { connectToDevice(it) } ?: connect()
            }
        }
    }

    private val callback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(device: BluetoothDevice?, registered: Boolean) {
            if (device != null) host = device
            emit(if (registered) "discoverable" else "disconnected")
        }
        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            host = device
            emit(
                if (state == BluetoothProfile.STATE_CONNECTED) "connected"
                else if (state == BluetoothProfile.STATE_CONNECTING) "discoverable"
                else "disconnected",
                if (state == BluetoothProfile.STATE_CONNECTED) device.name else null
            )
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

    fun onHidReady() {
        pendingAddress?.let { address ->
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || ActivityCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) {
                adapter?.getRemoteDevice(address)?.let { hid?.connect(it) }
            }
        }
    }
}
