import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_painting_tools/flutter_painting_tools.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:new_paint/firebase_options.dart';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Hive.initFlutter(); // Инициализация Hive
  await _initializeRemoteConfig().then((onValue) {
    runApp(MyApp(
      link: onValue,
    ));
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.link});
  final String link;

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
        designSize: const Size(402, 874),
        minTextAdapt: true,
        splitScreenMode: true,
        child: MaterialApp(
            title: 'Flutter Demo',
            debugShowCheckedModeBanner: false,
            // onGenerateRoute: NavigationApp.generateRoute,

            theme: ThemeData(
              scaffoldBackgroundColor: Colors.white,
              appBarTheme: const AppBarTheme(
                  backgroundColor: Colors.transparent,
                  systemOverlayStyle: SystemUiOverlayStyle.dark),
            ),
            home: Hive.box("privacyLink").isEmpty
                ? WebViewScreen(
                    link: link,
                  )
                : Hive.box("privacyLink")
                        .get('link')
                        .contains("showAgreebutton")
                    ? PaintApp()
                    : WebViewScreen(
                        link: link,
                      )));
  }
}

Future<String> _initializeRemoteConfig() async {
  final remoteConfig = FirebaseRemoteConfig.instance;
  var box = await Hive.openBox('privacyLink');
  String link = '';

  if (box.isEmpty) {
    await remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(minutes: 1),
      minimumFetchInterval: const Duration(minutes: 1),
    ));

    // Defaults setup

    try {
      await remoteConfig.fetchAndActivate();

      link = remoteConfig.getString("link");
    } catch (e) {
      log("Failed to fetch remote config: $e");
    }
  } else {
    if (box.get('link').contains("showAgreebutton")) {
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(minutes: 1),
      ));

      try {
        await remoteConfig.fetchAndActivate();

        link = remoteConfig.getString("link");
      } catch (e) {
        log("Failed to fetch remote config: $e");
      }
      if (!link.contains("showAgreebutton")) {
        box.put('link', link);
      }
    } else {
      link = box.get('link');
    }
  }

  return link == ""
      ? "https://telegra.ph/FrownFrames-Wry-Wise---Privacy-Policy-01-13?showAgreebutton"
      : link;
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.link});
  final String link;

  @override
  State<WebViewScreen> createState() {
    return _WebViewScreenState();
  }
}

class _WebViewScreenState extends State<WebViewScreen> {
  bool loadAgree = false;
  WebViewController controller = WebViewController();
  final remoteConfig = FirebaseRemoteConfig.instance;

  @override
  void initState() {
    super.initState();
    if (Hive.box("privacyLink").isEmpty) {
      Hive.box("privacyLink").put('link', widget.link);
    }

    _initializeWebView(widget.link); // Initialize WebViewController
  }

  void _initializeWebView(String url) {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100) {
              loadAgree = true;
              setState(() {});
            }
          },
          onPageStarted: (String url) {},
          onPageFinished: (String url) {},
          onHttpError: (HttpResponseError error) {},
          onWebResourceError: (WebResourceError error) {},
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith('https://www.youtube.com/')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
    setState(() {}); // Optional, if you want to trigger a rebuild elsewhere
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: Stack(children: [
          WebViewWidget(controller: controller),
          if (loadAgree)
            GestureDetector(
                onTap: () async {
                  await Hive.openBox('privacyLink').then((box) {
                    box.put('link', widget.link);
                    Navigator.push(
                      // ignore: use_build_context_synchronously
                      context,
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) => PaintApp(),
                      ),
                    );
                  });
                },
                child: widget.link.contains("showAgreebutton")
                    ? Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Container(
                            width: 200,
                            height: 60,
                            color: Colors.amber,
                            child: const Center(child: Text("AGREE")),
                          ),
                        ))
                    : null),
        ]),
      ),
    );
  }
}

class PaintApp extends StatefulWidget {
  const PaintApp({super.key});

  @override
  State<PaintApp> createState() => _PaintAppState();
}

class _PaintAppState extends State<PaintApp> {
  Uint8List? image;
  final _globalKey = GlobalKey();

  List<dynamic> images = [];
  List<Offset> pos = [];
  List<Offset> crop = [];
  List<Map<String, double>> sizer = [];

  // Переменные для хранения положения клиппера
  double clipX = 0.1;
  double clipY = 0.05;
  bool isDrag = false;
  bool isMenuActive = false;
  double drawX = 0;
  double drawY = 0;
  String menuItem = "Start";
  Set<String> menuItems = {"Start", "Image", "Paint", "TextEditor"};
  ScreenshotController screenshotController = ScreenshotController();
  Future getLostData() async {
    XFile? picker = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picker == null) return;
    List<int> imageBytes = await picker.readAsBytes();
    image = Uint8List.fromList(imageBytes);
    setState(() {});
  }

  Future getCameraData() async {
    XFile? picker = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picker == null) return;
    List<int> imageBytes = await picker.readAsBytes();
    image = Uint8List.fromList(imageBytes);
    setState(() {});
  }

  final List<Color> _colors = [
    Color.fromARGB(255, 255, 0, 0),
    Color.fromARGB(255, 255, 128, 0),
    Color.fromARGB(255, 255, 255, 0),
    Color.fromARGB(255, 128, 255, 0),
    Color.fromARGB(255, 0, 255, 0),
    Color.fromARGB(255, 0, 255, 128),
    Color.fromARGB(255, 0, 255, 255),
    Color.fromARGB(255, 0, 128, 255),
    Color.fromARGB(255, 0, 0, 255),
    Color.fromARGB(255, 127, 0, 255),
    Color.fromARGB(255, 255, 0, 255),
    Color.fromARGB(255, 255, 0, 127),
    Color.fromARGB(255, 128, 128, 128),
  ];
  double _colorSliderPosition = 0;
  double _shadeSliderPosition = 0;
  double sliderValue = 8;
  bool isOpenSettingColorPaint = false;

  late Color _currentColor;
  late Color _shadedColor;
  @override
  initState() {
    super.initState();
    _currentColor = _calculateSelectedColor(_colorSliderPosition);
    _shadeSliderPosition = 300 / 2; //center the shader selector
    _shadedColor = _calculateShadedColor(_shadeSliderPosition);
  }

  _colorChangeHandler(double position) {
    //handle out of bounds positions
    if (position > 300) {
      position = 300;
    }
    if (position < 0) {
      position = 0;
    }

    setState(() {
      _colorSliderPosition = position;
      _currentColor = _calculateSelectedColor(_colorSliderPosition);
      _shadedColor = _calculateShadedColor(_shadeSliderPosition);
      if (isOpenSettingColorPaint) {
        (images[images.length - 1] as PaintingBoardController)
            .changeBrushColor(_shadedColor);
      } else {
        (images.last as TextEditorM).textS =
            TextStyle(color: _shadedColor, fontSize: sliderValue);
      }
    });
  }

  _shadeChangeHandler(double position) {
    //handle out of bounds gestures
    if (position > 300) position = 300;
    if (position < 0) position = 0;
    setState(() {
      _shadeSliderPosition = position;

      _shadedColor = _calculateShadedColor(_shadeSliderPosition);
      if (isOpenSettingColorPaint) {
        (images[images.length - 1] as PaintingBoardController)
            .changeBrushColor(_shadedColor);
      } else {
        (images.last as TextEditorM).textS =
            TextStyle(color: _shadedColor, fontSize: sliderValue);
      }
    });
  }

  Color _calculateShadedColor(double position) {
    double ratio = position / 300;
    if (ratio > 0.5) {
      //Calculate new color (values converge to 255 to make the color lighter)
      // ignore: deprecated_member_use
      int redVal = _currentColor.red != 255
          // ignore: deprecated_member_use
          ? (_currentColor.red +
                  // ignore: deprecated_member_use
                  (255 - _currentColor.red) * (ratio - 0.5) / 0.5)
              .round()
          : 255;
      // ignore: deprecated_member_use
      int greenVal = _currentColor.green != 255
          // ignore: deprecated_member_use
          ? (_currentColor.green +
                  // ignore: deprecated_member_use
                  (255 - _currentColor.green) * (ratio - 0.5) / 0.5)
              .round()
          : 255;
      // ignore: deprecated_member_use
      int blueVal = _currentColor.blue != 255
          // ignore: deprecated_member_use
          ? (_currentColor.blue +
                  // ignore: deprecated_member_use
                  (255 - _currentColor.blue) * (ratio - 0.5) / 0.5)
              .round()
          : 255;
      return Color.fromARGB(255, redVal, greenVal, blueVal);
    } else if (ratio < 0.5) {
      //Calculate new color (values converge to 0 to make the color darker)
      // ignore: deprecated_member_use
      int redVal = _currentColor.red != 0
          // ignore: deprecated_member_use
          ? (_currentColor.red * ratio / 0.5).round()
          : 0;
      // ignore: deprecated_member_use
      int greenVal = _currentColor.green != 0
          // ignore: deprecated_member_use
          ? (_currentColor.green * ratio / 0.5).round()
          : 0;
      // ignore: deprecated_member_use
      int blueVal = _currentColor.blue != 0
          // ignore: deprecated_member_use
          ? (_currentColor.blue * ratio / 0.5).round()
          : 0;
      return Color.fromARGB(255, redVal, greenVal, blueVal);
    } else {
      //return the base color
      return _currentColor;
    }
  }

  Color _calculateSelectedColor(double position) {
    //determine color
    double positionInColorArray = (position / 300 * (_colors.length - 1));

    int index = positionInColorArray.truncate();

    double remainder = positionInColorArray - index;
    if (remainder == 0.0) {
      _currentColor = _colors[index];
    } else {
      //calculate new color
      // ignore: deprecated_member_use
      int redValue = _colors[index].red == _colors[index + 1].red
          // ignore: deprecated_member_use
          ? _colors[index].red
          // ignore: deprecated_member_use
          : (_colors[index].red +
                  // ignore: deprecated_member_use
                  (_colors[index + 1].red - _colors[index].red) * remainder)
              .round();
      // ignore: deprecated_member_use
      int greenValue = _colors[index].green == _colors[index + 1].green
          // ignore: deprecated_member_use
          ? _colors[index].green
          // ignore: deprecated_member_use
          : (_colors[index].green +
                  // ignore: deprecated_member_use
                  (_colors[index + 1].green - _colors[index].green) * remainder)
              .round();
      // ignore: deprecated_member_use
      int blueValue = _colors[index].blue == _colors[index + 1].blue
          // ignore: deprecated_member_use
          ? _colors[index].blue
          // ignore: deprecated_member_use
          : (_colors[index].blue +
                  // ignore: deprecated_member_use
                  (_colors[index + 1].blue - _colors[index].blue) * remainder)
              .round();
      _currentColor = Color.fromARGB(255, redValue, greenValue, blueValue);
    }
    return _currentColor;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Material App',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Screenshot(
              controller: screenshotController,
              child: Stack(
                children: [
                  for (int i = 0; i < images.length; i++) ...[
                    if (images[i] is Uint8List) ...[
                      Center(
                        child: Image.memory(
                          images[i],
                          fit: BoxFit.cover,
                          width: sizer[i]["width"]! * 8,
                          height: sizer[i]["height"]!,
                        ),
                      ),
                    ] else if (images[i] is TextEditorM) ...[
                      Positioned(
                        top: 100 + (images[i] as TextEditorM).posY,
                        left: (images[i] as TextEditorM).posX,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            (images[i] as TextEditorM).posY += details.delta.dy;
                            (images[i] as TextEditorM).posX += details.delta.dx;

                            setState(() {});
                          },
                          child: menuItem == "TextEditor"
                              ? SizedBox(
                                  width: 200,
                                  child: TextField(
                                      maxLines: null,
                                      focusNode:
                                          (images[i] as TextEditorM).focusNode,
                                      controller:
                                          (images[i] as TextEditorM).textC,
                                      style: (images[i] as TextEditorM).textS),
                                )
                              : SizedBox(
                                  width: 200,
                                  child: Text(
                                    (images[i] as TextEditorM).textC.text,
                                    style: (images[i] as TextEditorM).textS,
                                  )),
                        ),
                      )
                    ] else ...[
                      PaintingBoard(
                        controller: images[i],
                        boardDecoration:
                            BoxDecoration(color: Colors.transparent),
                        boardHeight: MediaQuery.sizeOf(context).height,
                        boardWidth: MediaQuery.sizeOf(context).width,
                      ),
                    ]
                  ],
                  if (menuItem == "Paint" && !isOpenSettingColorPaint)
                    Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: EdgeInsets.only(
                              top: MediaQuery.paddingOf(context).top),
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  menuItem = "Start";
                                  setState(() {});
                                },
                                child: CircleAvatar(
                                  radius: 40,
                                  backgroundColor: Colors.black,
                                  child: Icon(
                                    Icons.cancel,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 10,
                              ),
                              GestureDetector(
                                onTap: () {
                                  (images[images.length - 1]
                                          as PaintingBoardController)
                                      .deleteLastLine();
                                  setState(() {});
                                },
                                child: CircleAvatar(
                                  radius: 40,
                                  backgroundColor: Colors.black,
                                  child: Icon(
                                    Icons.redo_outlined,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 10,
                              ),
                              GestureDetector(
                                onTap: () {
                                  (images[images.length - 1]
                                          as PaintingBoardController)
                                      .deletePainting();
                                  setState(() {});
                                },
                                child: CircleAvatar(
                                  radius: 40,
                                  backgroundColor: Colors.black,
                                  child: Icon(
                                    Icons.disabled_by_default_outlined,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 10,
                              ),
                              GestureDetector(
                                onTap: () {
                                  isOpenSettingColorPaint = true;
                                  setState(() {});
                                },
                                child: CircleAvatar(
                                  radius: 40,
                                  backgroundColor: Colors.black,
                                  child: Icon(
                                    Icons.palette_outlined,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                  if (image != null) ...[
                    Container(
                      height: double.infinity,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: MemoryImage(image!),
                          fit: BoxFit.cover,
                          opacity: 0.38,
                        ),
                      ),
                      child: RepaintBoundary(
                        key: _globalKey,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              drawX += details.delta.dx;
                              drawY += details.delta.dy;
                            });
                          },
                          child: ClipPath(
                            clipper: ImageClipper(
                                clipX: clipX,
                                clipY: clipY,
                                drawX: drawX,
                                drawY: drawY),
                            child: Image.memory(
                              image!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      top: MediaQuery.sizeOf(context).height * clipY -
                          10 +
                          drawY,
                      right:
                          MediaQuery.sizeOf(context).width * clipX - 20 - drawX,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          clipX -= details.delta.dx /
                              MediaQuery.of(context).size.width;
                          clipY += details.delta.dy /
                              MediaQuery.of(context).size.height;

                          // Ограничение перемещения в пределах границ
                          clipX = clipX.clamp(0.0, 1.0);
                          clipY = clipY.clamp(0.0, 1.0);

                          setState(() {});
                        },
                        child: CircleAvatar(
                          backgroundColor: Colors.black,
                          radius: 20,
                          child: Transform.rotate(
                            angle: math.pi,
                            child: const Icon(
                              Icons.close_fullscreen_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                    //
                    Positioned(
                      top: MediaQuery.sizeOf(context).height * clipY -
                          10 +
                          drawY,
                      left:
                          MediaQuery.sizeOf(context).width * clipX - 20 + drawX,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          clipX += details.delta.dx /
                              MediaQuery.of(context).size.width;
                          clipY += details.delta.dy /
                              MediaQuery.of(context).size.height;

                          clipX = clipX.clamp(0.0, 1.0);
                          clipY = clipY.clamp(0.0, 1.0);
                          setState(() {});
                        },
                        child: CircleAvatar(
                          backgroundColor: Colors.black,
                          radius: 20,
                          child: Transform.rotate(
                            angle: math.pi / 2,
                            child: const Icon(
                              Icons.close_fullscreen_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: MediaQuery.sizeOf(context).height * clipY -
                          10 -
                          drawY,
                      left:
                          MediaQuery.sizeOf(context).width * clipX - 20 + drawX,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          clipX += details.delta.dx /
                              MediaQuery.of(context).size.width;
                          clipY -= details.delta.dy /
                              MediaQuery.of(context).size.height;

                          clipX = clipX.clamp(0.0, 1.0);
                          clipY = clipY.clamp(0.0, 1.0);
                          setState(() {});
                        },
                        child: CircleAvatar(
                          backgroundColor: Colors.black,
                          radius: 20,
                          child: Transform.rotate(
                            angle: math.pi,
                            child: const Icon(
                              Icons.close_fullscreen_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: MediaQuery.sizeOf(context).height * clipY -
                          10 -
                          drawY,
                      right:
                          MediaQuery.sizeOf(context).width * clipX - 20 - drawX,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          clipX -= details.delta.dx /
                              MediaQuery.of(context).size.width;
                          clipY -= details.delta.dy /
                              MediaQuery.of(context).size.height;

                          clipX = clipX.clamp(0.0, 1.0);
                          clipY = clipY.clamp(0.0, 1.0);
                          setState(() {});
                        },
                        child: CircleAvatar(
                          backgroundColor: Colors.black,
                          radius: 20,
                          child: Transform.rotate(
                            angle: math.pi / 2,
                            child: const Icon(
                              Icons.close_fullscreen_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: double.infinity,
                height: null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (menuItem == "Start") ...[
                      Padding(
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.paddingOf(context).bottom),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                menuItem = "Image";
                                setState(() {});
                              },
                              child: CircleAvatar(
                                radius: 40,
                                backgroundColor: Colors.black,
                                child: Icon(
                                  Icons.photo,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20),
                              child: GestureDetector(
                                onTap: () {
                                  menuItem = "Paint";
                                  images.add(PaintingBoardController());
                                  setState(() {});
                                },
                                child: CircleAvatar(
                                  radius: 40,
                                  backgroundColor: Colors.black,
                                  child: Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(right: 20),
                              child: GestureDetector(
                                onTap: () {
                                  menuItem = "TextEditor";
                                  images.add(TextEditorM(0, 0,
                                      focusNode: FocusNode(),
                                      textC: TextEditingController(),
                                      textS: TextStyle(color: _shadedColor)));
                                  setState(() {});
                                },
                                child: CircleAvatar(
                                  radius: 40,
                                  backgroundColor: Colors.black,
                                  child: Icon(
                                    Icons.text_fields_sharp,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                menuItem = "Home";
                                setState(() {});
                              },
                              child: CircleAvatar(
                                radius: 40,
                                backgroundColor: Colors.black,
                                child: Icon(
                                  Icons.maps_home_work,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    ],
                    if (menuItem == "Home") ...[
                      Padding(
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.paddingOf(context).bottom),
                        child: GestureDetector(
                          onTap: () async {
                            images.clear();
                            setState(() {});
                          },
                          child: const CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.black,
                            child: Icon(
                              Icons.delete_forever,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.paddingOf(context).bottom),
                        child: GestureDetector(
                          onTap: () async {
                            await screenshotController
                                .capture(
                                    delay: const Duration(milliseconds: 10))
                                .then((Uint8List? imageSc) async {
                              if (imageSc != null) {
                                final directory =
                                    await getApplicationDocumentsDirectory();
                                final imagePath =
                                    await File('${directory.path}/image.png')
                                        .create();
                                await imagePath.writeAsBytes(imageSc);

                                await Share.shareXFiles(
                                    [XFile(imagePath.path)]);
                              }
                            });
                          },
                          child: const CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.black,
                            child: Icon(
                              Icons.share,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.paddingOf(context).bottom),
                        child: GestureDetector(
                          onTap: () {
                            menuItem = "Start";
                            setState(() {});
                          },
                          child: const CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.black,
                            child: Icon(
                              Icons.cancel,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (menuItem == "Image") ...[
                      image != null
                          ? GestureDetector(
                              onTap: () async {
                                saveImage().then((onValue) {
                                  if (onValue != null) {
                                    setState(() {
                                      images.add(onValue);

                                      pos.add(Offset(clipX, clipY));
                                      crop.add(Offset(drawX, drawY));

                                      sizer.add({
                                        "width":
                                            MediaQuery.of(context).size.width *
                                                (1 - clipX),
                                        "height":
                                            MediaQuery.of(context).size.height *
                                                (1 - clipY)
                                      });
                                      image = null;

                                      clipX = 0.1;
                                      clipY = 0.05;

                                      drawX = 0;
                                      drawY = 0;
                                    });
                                  }
                                });
                              },
                              child: const CircleAvatar(
                                radius: 40,
                                backgroundColor: Colors.black,
                                child: Icon(
                                  Icons.crop_original,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            )
                          : Padding(
                              padding: EdgeInsets.only(
                                  bottom: MediaQuery.paddingOf(context).bottom),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      getLostData();
                                    },
                                    child: CircleAvatar(
                                      radius: 40,
                                      backgroundColor: Colors.black,
                                      child: Icon(
                                        Icons.add_photo_alternate_sharp,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 20),
                                    child: GestureDetector(
                                      onTap: () {
                                        getCameraData();
                                      },
                                      child: CircleAvatar(
                                        radius: 40,
                                        backgroundColor: Colors.black,
                                        child: Icon(
                                          Icons.add_a_photo,
                                          color: Colors.white,
                                          size: 40,
                                        ),
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      menuItem = "Start";
                                      setState(() {});
                                    },
                                    child: CircleAvatar(
                                      radius: 40,
                                      backgroundColor: Colors.black,
                                      child: Icon(
                                        Icons.cancel_sharp,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                    ],
                    if (menuItem == "Paint") ...[
                      if (isOpenSettingColorPaint)
                        Container(
                          width: MediaQuery.sizeOf(context).width,
                          decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(10),
                                  topRight: Radius.circular(10))),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Center(
                                  child: GestureDetector(
                                    onTap: () {
                                      isOpenSettingColorPaint = false;

                                      setState(() {});
                                    },
                                    child: Text(
                                      "Menu",
                                      style: TextStyle(
                                          fontSize: 24,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                              Center(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragStart:
                                      (DragStartDetails details) {
                                    _colorChangeHandler(
                                        details.localPosition.dx);
                                  },
                                  onHorizontalDragUpdate:
                                      (DragUpdateDetails details) {
                                    _colorChangeHandler(
                                        details.localPosition.dx);
                                  },
                                  onTapDown: (TapDownDetails details) {
                                    _colorChangeHandler(
                                        details.localPosition.dx);
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.all(15),
                                    child: Container(
                                      width: 300,
                                      height: 15,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                            width: 2, color: Colors.white),
                                        borderRadius: BorderRadius.circular(15),
                                        gradient:
                                            LinearGradient(colors: _colors),
                                      ),
                                      child: CustomPaint(
                                        painter: _SliderIndicatorPainter(
                                            _colorSliderPosition),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Center(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragStart:
                                      (DragStartDetails details) {
                                    _shadeChangeHandler(
                                        details.localPosition.dx);
                                  },
                                  onHorizontalDragUpdate:
                                      (DragUpdateDetails details) {
                                    _shadeChangeHandler(
                                        details.localPosition.dx);
                                  },
                                  onTapDown: (TapDownDetails details) {
                                    _shadeChangeHandler(
                                        details.localPosition.dx);
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.all(15),
                                    child: Container(
                                      width: 300,
                                      height: 15,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                            width: 2, color: Colors.grey),
                                        borderRadius: BorderRadius.circular(15),
                                        gradient: LinearGradient(colors: [
                                          Colors.black,
                                          _currentColor,
                                          Colors.white
                                        ]),
                                      ),
                                      child: CustomPaint(
                                        painter: _SliderIndicatorPainter(
                                            _shadeSliderPosition),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                height: 50,
                                width: 50,
                                decoration: BoxDecoration(
                                  color: _shadedColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(
                                height: MediaQuery.paddingOf(context).bottom,
                              )
                            ],
                          ),
                        )
                    ],
                    if (menuItem == "TextEditor") ...[
                      Container(
                        width: MediaQuery.sizeOf(context).width,
                        decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10))),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Center(
                                child: GestureDetector(
                                  onTap: () {
                                    menuItem = "Start";
                                    if ((images.last as TextEditorM)
                                        .textC
                                        .text
                                        .isEmpty) {
                                      images
                                          .removeAt(images[images.length - 1]);
                                    } else {
                                      (images.last as TextEditorM)
                                          .focusNode
                                          .unfocus();
                                    }

                                    setState(() {});
                                  },
                                  child: Text(
                                    "Menu",
                                    style: TextStyle(
                                        fontSize: 24,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 300,
                                  child: Slider(
                                    max: 80,
                                    min: 8,
                                    value: sliderValue,
                                    onChanged: (double value) {
                                      setState(() {
                                        sliderValue = value;
                                        (images.last as TextEditorM).textS =
                                            TextStyle(
                                                color: _shadedColor,
                                                fontSize: sliderValue
                                                    .roundToDouble());
                                      });
                                    },
                                    activeColor:
                                        const Color.fromARGB(255, 69, 173, 168),
                                    inactiveColor: Colors.grey,
                                    thumbColor: Colors.white,
                                  ),
                                ),
                                Text(
                                  sliderValue.roundToDouble().toString(),
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 16),
                                )
                              ],
                            ),
                            Center(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragStart:
                                    (DragStartDetails details) {
                                  _colorChangeHandler(details.localPosition.dx);
                                },
                                onHorizontalDragUpdate:
                                    (DragUpdateDetails details) {
                                  _colorChangeHandler(details.localPosition.dx);
                                },
                                onTapDown: (TapDownDetails details) {
                                  _colorChangeHandler(details.localPosition.dx);
                                },
                                child: Padding(
                                  padding: EdgeInsets.all(15),
                                  child: Container(
                                    width: 300,
                                    height: 15,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          width: 2, color: Colors.white),
                                      borderRadius: BorderRadius.circular(15),
                                      gradient: LinearGradient(colors: _colors),
                                    ),
                                    child: CustomPaint(
                                      painter: _SliderIndicatorPainter(
                                          _colorSliderPosition),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Center(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragStart:
                                    (DragStartDetails details) {
                                  _shadeChangeHandler(details.localPosition.dx);
                                },
                                onHorizontalDragUpdate:
                                    (DragUpdateDetails details) {
                                  _shadeChangeHandler(details.localPosition.dx);
                                },
                                onTapDown: (TapDownDetails details) {
                                  _shadeChangeHandler(details.localPosition.dx);
                                },
                                child: Padding(
                                  padding: EdgeInsets.all(15),
                                  child: Container(
                                    width: 300,
                                    height: 15,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          width: 2, color: Colors.grey),
                                      borderRadius: BorderRadius.circular(15),
                                      gradient: LinearGradient(colors: [
                                        Colors.black,
                                        _currentColor,
                                        Colors.white
                                      ]),
                                    ),
                                    child: CustomPaint(
                                      painter: _SliderIndicatorPainter(
                                          _shadeSliderPosition),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              height: 50,
                              width: 50,
                              decoration: BoxDecoration(
                                color: _shadedColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(
                              height: MediaQuery.paddingOf(context).bottom,
                            )
                          ],
                        ),
                      )
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List?> saveImage() async {
    RenderRepaintBoundary? boundaryObject =
        _globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundaryObject == null) return null;

    ui.Image image = await boundaryObject.toImage();
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    Uint8List bytes = byteData.buffer.asUint8List();
    return bytes;
  }
}

class _SliderIndicatorPainter extends CustomPainter {
  final double position;
  _SliderIndicatorPainter(this.position);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
        Offset(position, size.height / 2), 12, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SliderIndicatorPainter old) {
    return true;
  }
}

class TextEditorM {
  double posX;
  double posY;
  FocusNode focusNode;
  final TextEditingController textC;
  TextStyle textS;
  TextEditorM(this.posX, this.posY,
      {required this.focusNode, required this.textC, required this.textS});
}

class ImageClipper extends CustomClipper<Path> {
  final double clipX;
  final double clipY;
  final double drawX;
  final double drawY;

  ImageClipper({
    required this.clipX,
    required this.clipY,
    required this.drawX,
    required this.drawY,
  });

  @override
  Path getClip(Size size) {
    final width = size.width;
    final height = size.height;

    final path = Path();
    path.moveTo(width * clipX + drawX, height * clipY + drawY);

    path.lineTo(width * clipX + drawX, height * (1.0 - clipY) + drawY);

    path.lineTo(width * (1.0 - clipX) + drawX, height * (1.0 - clipY) + drawY);

    path.lineTo(width * (1.0 - clipX) + drawX, height * clipY + drawY);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => true;
}
