import 'dart:async';

import 'package:dart_chromecast/casting/cast_device.dart';
import 'package:dart_chromecast/casting/cast_media.dart';
import 'package:dart_chromecast/casting/cast_sender.dart';
import 'package:dart_chromecast/casting/cast_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmasterclass/config/app_config.dart';
import 'package:twmasterclass/home_screen/service_discovery.dart';
import 'package:twmasterclass/home_screen/device_picker.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  InAppWebViewController webView;

  VoidCallback listener;

  bool video = true;
  bool videoPlayed = false;
  bool videoLoaded = false;
  bool _isPlaying = false;
  bool _isPaused = false;

  String _videoUrl = '';

  bool _servicesFound = false;
  bool _castConnected = false;
  ServiceDiscovery _serviceDiscovery;
  CastSender _castSender;
  List _videoItems = [];

  @override
  void initState() {
    super.initState();
    _reconnectOrDiscover();
  }

  _reconnectOrDiscover() async {
    bool reconnectSuccess = await reconnect();
    if (!reconnectSuccess) {
      _discover();
    }
  }

  _discover() async {
    _serviceDiscovery = ServiceDiscovery();
    _serviceDiscovery.changes.listen((_) {
      setState(() => _servicesFound = _serviceDiscovery.foundServices.length > 0);
    });
    _serviceDiscovery.startDiscovery();
  }

  Future<bool> reconnect() async {
    final prefs = await SharedPreferences.getInstance();
    String host = prefs.getString('cast_session_host');
    String name = prefs.getString('cast_session_device_name');
    String type = prefs.getString('cast_session_device_type');
    String sourceId = prefs.getString('cast_session_sender_id');
    String destinationId = prefs.getString('cast_session_destination_id');
    if (null == host || null == name || null == type || null == sourceId || null == destinationId) {
      return false;
    }
    CastDevice device = CastDevice(
        name: name, host: host, port: prefs.getInt('cast_session_port') ?? 8009, type: type);
    _castSender = CastSender(device);
    StreamSubscription subscription =
        _castSender.castSessionController.stream.listen((CastSession castSession) {
      print('CastSession update ${castSession.isConnected.toString()}');
      if (castSession.isConnected) {
        _castSessionIsConnected(castSession);
      }
    });
    bool didReconnect = await _castSender.reconnect(
      sourceId: sourceId,
      destinationId: destinationId,
    );
    if (!didReconnect) {
      subscription.cancel();
      _castSender = null;
    }
    return didReconnect;
  }

  void disconnect() async {
    if (null != _castSender) {
      await _castSender.disconnect();
      final prefs = await SharedPreferences.getInstance();
      prefs.remove('cast_session_host');
      prefs.remove('cast_session_port');
      prefs.remove('cast_session_device_name');
      prefs.remove('cast_session_device_type');
      prefs.remove('cast_session_sender_id');
      prefs.remove('cast_session_destination_id');
      setState(() {
        _castSender = null;
        _servicesFound = false;
        _castConnected = false;
        _discover();
      });
    }
  }

  void _castSessionIsConnected(CastSession castSession) async {
    setState(() {
      _castConnected = true;
    });

    final prefs = await SharedPreferences.getInstance();
    prefs.setString('cast_session_host', _castSender.device.host);
    prefs.setInt('cast_session_port', _castSender.device.port);
    prefs.setString('cast_session_device_name', _castSender.device.name);
    prefs.setString('cast_session_device_type', _castSender.device.type);
    prefs.setString('cast_session_sender_id', castSession.sourceId);
    prefs.setString('cast_session_destination_id', castSession.destinationId);
  }

  void _connectToDevice(CastDevice device) async {
    // stop discovery, only has to be on when we're not casting already
    _serviceDiscovery.stopDiscovery();

    _castSender = CastSender(device);
    StreamSubscription subscription =
        _castSender.castSessionController.stream.listen((CastSession castSession) {
      if (castSession.isConnected) {
        _castSessionIsConnected(castSession);
      }
    });
    bool connected = await _castSender.connect();
    if (!connected) {
      // show error message...
      subscription.cancel();
      _castSender = null;
      return;
    }

    // SAVE STATE SO WE CAN TRY TO RECONNECT!
    _castSender.launch();
  }

  Future<bool> _onBack() async {
    bool goBack;
    var value = await webView.canGoBack();
    if (value) {
      webView.goBack();
      return false;
    } else {
      await showDialog(
        context: context,
        builder: (context) => new AlertDialog(
          title: new Text('Exit'),
          content: new Text('Do you want to exit the app ? '),
          actions: <Widget>[
            new FlatButton(
              onPressed: () {
                Navigator.of(context).pop(false);
                setState(() {
                  goBack = false;
                });
              },
              child: new Text('NO'),
            ),
            new FlatButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  goBack = true;
                });
              },
              child: new Text('YES'),
            ),
          ],
        ),
      );
      if (goBack) Navigator.pop(context);
      return goBack;
    }
  }

  _playToggle() {
    setState(() {
      _isPaused = !_isPaused;
    });
  }

  _showAlertDialog(BuildContext context) {
    // set up the button
    Widget okButton = FlatButton(
      child: Text("OK"),
      onPressed: () {
        Navigator.of(context).pop();
      },
    );
    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("Purchase available via website"),
      content: Text("Please visit www.twmasterclass.com"),
      actions: [
        okButton,
      ],
    );
    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> actionButtons = [];
    if (_servicesFound || _castConnected) {
      IconData iconData = _castConnected ? Icons.cast_connected : Icons.cast;
      actionButtons.add(
        IconButton(
          icon: Icon(iconData),
          onPressed: () {
            if (_castConnected) {
              print('SHOW DISCONNECT DIALOG!');
              // for now just immediately disconnect
              disconnect();
              return;
            }
            Navigator.of(context).push(new MaterialPageRoute(
              builder: (BuildContext context) => DevicePicker(
                  serviceDiscovery: _serviceDiscovery, onDevicePicked: _connectToDevice),
              fullscreenDialog: true,
            ));
          },
        ),
      );
    }
    return WillPopScope(
      onWillPop: _onBack,
      child: SafeArea(
        child: Scaffold(
            appBar: AppBar(
                    title: Text(appName),
                    centerTitle: true,
                    actions: actionButtons,
                  ),
            body: Stack(
              children: [
                InAppWebView(
                  initialUrl: website,
                  initialOptions: InAppWebViewGroupOptions(
                      crossPlatform: InAppWebViewOptions(
                    debuggingEnabled: true,
                    javaScriptEnabled: true,
                    useOnLoadResource: true,
                    useShouldOverrideUrlLoading: true,
                  )),
                  onWebViewCreated: (InAppWebViewController controller) {
                    webView = controller;
                  },
                  onLoadResource: (InAppWebViewController controller, LoadedResource resource) {
                    if (resource.url.contains('.mp4') || resource.url.contains('.m3u8')) {
                      _videoUrl = resource.url;
                      _videoItems = [
                        CastMedia(
                          title: 'Chromecast video 1',
                          contentId: _videoUrl,
                          images: [
                            'https://static1.squarespace.com/static/5647f7e9e4b0f54883c66275/5647f9afe4b0caa2cf189d56/56489d67e4b0734a6c410a64/1447599477357/?format=1500w'
                          ],
                        ),
                      ];
                    }
                  },
                  shouldOverrideUrlLoading: (InAppWebViewController controller,
                      ShouldOverrideUrlLoadingRequest request) async {
                    if (request.url.contains('membership-checkout') ||
                        request.url.contains('cart')) {
                      _showAlertDialog(context);
                      return ShouldOverrideUrlLoadingAction.CANCEL;
                    }
                    return ShouldOverrideUrlLoadingAction.ALLOW;
                  },
                ),
                (null != _castSender)
                    ? Column(
                        children: [
                          Expanded(
                            child: Container(
                              color: Colors.black87,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "Casting To:",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20.0,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      _castSender.device.friendlyName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20.0,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            color: Colors.black87,
                            height: 100,
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: <Widget>[
                                  FlatButton(
                                    child: Icon(
                                      Icons.fast_rewind,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      //rewind 10 seconds from current video position
                                      _castSender.seek(
                                          _castSender.castSession.castMediaStatus.position - 10.0);
                                    },
                                  ),
                                  FlatButton(
                                    child: (_isPaused == false)
                                        ? Icon(
                                            Icons.play_arrow,
                                            color: Colors.white,
                                          )
                                        : Icon(
                                            Icons.pause,
                                            color: Colors.white,
                                          ),
                                    onPressed: () {
                                      if (_isPlaying == false) {
                                        CastMedia castMedia = _videoItems[0];
                                        _castSender.load(castMedia);
                                        setState(() {
                                          _isPlaying = true;
                                        });
                                      }
                                      _playToggle();
                                      _castSender.togglePause();
                                    },
                                  ),
                                  FlatButton(
                                    child: Icon(
                                      Icons.stop,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      if (_isPlaying) {
                                        setState(() {
                                          _isPlaying = false;
                                          _isPaused = false;
                                        });
                                      }
                                      _castSender.stop();
                                    },
                                  ),
                                  FlatButton(
                                    child: Icon(
                                      Icons.fast_forward,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      //fast forward 10 seconds from current video position
                                      _castSender.seek(
                                          _castSender.castSession.castMediaStatus.position + 10.0);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : Container(),
              ],
            )),
      ),
    );
  }
}
