import 'package:flutter/material.dart';

const sentraBlackWordmarkAsset = 'assets/images/sentra-wordmark-black.png';
const sentraWhiteWordmarkAsset = 'assets/images/sentra-wordmark-white.png';

String sentraWordmarkAssetFor(Brightness brightness) =>
    brightness == Brightness.dark
    ? sentraWhiteWordmarkAsset
    : sentraBlackWordmarkAsset;
