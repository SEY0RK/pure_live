import 'dart:math' as math;

import 'package:rxdart/rxdart.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/modules/live_play/states/ui_state.dart';
import 'package:pure_live/player/core/portrait_stream_support.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku/danmaku_tab.dart';
import 'package:pure_live/modules/live_play/widgets/layout/live_play_shell.dart';
import 'package:pure_live/modules/live_play/widgets/layout/live_play_video.dart';
import 'package:pure_live/modules/live_play/widgets/layout/live_play_header.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/widgets/resolution_selector/resolutions_row.dart';

enum LivePlayLayoutType { portrait, landscapeStack, desktop }

/// Width up to which the room stacks video above the danmaku panel.
const double livePlayPortraitStackMaxWidth = 680;

/// Picks the page topology from the window state together with the live
/// source's own orientation.
///
/// A phone-sized window always keeps the single stacked column. A large window
/// keeps the side panel only for a portrait programme: a landscape programme
/// leaves most of that panel's height unused, so it stacks the same way a
/// folded phone does. The orientation comes from the decoded frame size, never
/// from the device's physical rotation, and the window width is the only
/// window-state signal available (the repository has no hinge/fold API).
LivePlayLayoutType resolveLivePlayLayoutType({
  required double width,
  required bool isPortraitSource,
  bool splitBySourceOrientation = false,
}) {
  if (width <= livePlayPortraitStackMaxWidth) return LivePlayLayoutType.portrait;
  if (splitBySourceOrientation && !isPortraitSource) return LivePlayLayoutType.landscapeStack;
  return LivePlayLayoutType.desktop;
}

/// Source aspect with a safe fallback for unknown or degenerate frame sizes.
double resolveLivePlayAspectRatio(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return 16 / 9;
  }
  final ratio = width / height;
  return ratio.isFinite && ratio > 0 ? ratio : 16 / 9;
}

class LivePlayLayout extends StatelessWidget {
  const LivePlayLayout({
    super.key,
    required this.video,
    required this.resolution,
    required this.danmaku,
    required this.layoutMode,
    this.showPanel = true,
    this.isPortraitSource = false,
    this.sourceAspectRatio = 16 / 9,
    this.splitBySourceOrientation = false,
    this.danmakuPanelHeight = defaultDanmakuPanelHeight,
  });

  /// Default floor for the danmaku list on this page.
  static const double defaultDanmakuPanelHeight = 220;

  /// Smallest list the layout will leave usable, even when the configured floor
  /// is smaller or the page is very short.
  static const double minimumDanmakuPanelHeight = 96;

  /// The quality selector row lives inside the panel above the list.
  static const double _resolutionReserve = 48;

  /// Width the side panel keeps in the portrait-source split.
  static const double minimumDesktopSplitPanelWidth = 240;

  final Widget video;
  final Widget resolution;
  final Widget danmaku;
  final PortraitLayoutMode layoutMode;
  final bool showPanel;

  /// Whether the live source is taller than it is wide.
  final bool isPortraitSource;

  /// Decoded source aspect, used to size the video box in a wide window.
  final double sourceAspectRatio;

  /// Whether a large window may choose its topology from the source
  /// orientation. Enabled on Android only, so the desktop player keeps its
  /// long-standing side panel.
  final bool splitBySourceOrientation;

  /// Minimum height the danmaku list keeps in this posture.
  ///
  /// The caller passes the value configured for the current window: the
  /// unfolded inner screen and the folded outer screen are tuned separately.
  final double danmakuPanelHeight;

  double get _sourceAspectRatio =>
      sourceAspectRatio.isFinite && sourceAspectRatio > 0 ? sourceAspectRatio : 16 / 9;

  @override
  Widget build(BuildContext context) {
    if (!showPanel) {
      return SizedBox.expand(
        child: ColoredBox(color: Colors.black, child: video),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        switch (resolveLivePlayLayoutType(
          width: constraints.maxWidth,
          isPortraitSource: isPortraitSource,
          splitBySourceOrientation: splitBySourceOrientation,
        )) {
          case LivePlayLayoutType.portrait:
            return _buildPortraitLayout(context, constraints);
          case LivePlayLayoutType.landscapeStack:
            return _buildLandscapeStack(context, constraints);
          case LivePlayLayoutType.desktop:
            return _buildDesktopLayout(context, constraints);
        }
      },
    );
  }

  /// Height the danmaku list keeps at minimum on this page.
  ///
  /// The floor stops the list from being squeezed to nothing in a short window.
  /// Whatever height the video does not need goes to the list, so the video
  /// never floats inside an unused black band.
  double _panelFloor(double availableHeight) {
    final height = availableHeight.isFinite ? availableHeight : 0.0;
    final configured = danmakuPanelHeight.isFinite ? danmakuPanelHeight : defaultDanmakuPanelHeight;
    // Never take more than 60% of a short page: an unclamped floor would invert
    // the problem and starve the video instead.
    final upperBound = math.max(minimumDanmakuPanelHeight, height * 0.6);
    return configured.clamp(minimumDanmakuPanelHeight, upperBound).toDouble();
  }

  double _videoHeightCap(double availableHeight) =>
      math.max(0.0, availableHeight - _panelFloor(availableHeight) - _resolutionReserve);

  Widget _buildPortraitLayout(BuildContext context, BoxConstraints constraints) {
    final panelColor = Theme.of(context).colorScheme.surface;
    final availableHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildVideo(context, constraints, maxHeight: _videoHeightCap(availableHeight)),
        Expanded(
          child: ColoredBox(
            color: panelColor,
            child: Column(
              children: [
                resolution,
                const Divider(height: 1),
                Expanded(child: danmaku),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Landscape programme in a large window: the video takes exactly the height
  /// its own aspect needs and the list absorbs everything left over.
  ///
  /// The previous version handed the whole leftover height to the video area and
  /// centred a fixed-aspect box inside it, so every pixel the 16:9 picture did
  /// not need showed up as a black band above and below it.
  Widget _buildLandscapeStack(BuildContext context, BoxConstraints constraints) {
    final panelColor = Theme.of(context).colorScheme.surface;
    final availableHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
    final naturalHeight = constraints.maxWidth / _sourceAspectRatio;
    final videoHeight = math.min(naturalHeight, _videoHeightCap(availableHeight));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: videoHeight,
          child: Center(
            child: AspectRatio(aspectRatio: _sourceAspectRatio, child: video),
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: panelColor,
            child: Column(
              children: [
                resolution,
                const Divider(height: 1),
                Expanded(child: danmaku),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context, BoxConstraints constraints) {
    final panelColor = Theme.of(context).colorScheme.surface;
    final maxWidth = constraints.maxWidth;
    final maxHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
    final double videoWidth;

    if (_sourceAspectRatio < 1) {
      // A portrait programme is taller than it is wide. Deriving the video
      // column from the source aspect keeps the picture edge-to-edge instead of
      // centring a 9:16 strip inside a 16:9 letterbox, and the width it frees
      // up goes to the danmaku list.
      final byHeight = maxHeight * _sourceAspectRatio;
      final ceiling = math.max(minimumDesktopSplitPanelWidth, maxWidth - minimumDesktopSplitPanelWidth);
      videoWidth = byHeight.clamp(0.0, ceiling).toDouble();
    } else {
      videoWidth = math.max(0.0, maxWidth - 340.0);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: videoWidth,
          child: Container(
            color: Colors.black,
            child: Center(
              child: AspectRatio(aspectRatio: _sourceAspectRatio, child: video),
            ),
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: panelColor,
            child: Column(
              children: [
                resolution,
                const Divider(height: 1),
                Expanded(child: danmaku),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideo(BuildContext context, BoxConstraints constraints, {double? maxHeight}) {
    switch (layoutMode) {
      case PortraitLayoutMode.balanced:
        final naturalHeight = constraints.maxWidth / (16 / 9);
        final height = maxHeight == null ? naturalHeight : math.min(naturalHeight, maxHeight);
        return SizedBox(
          width: constraints.maxWidth,
          height: height,
          child: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(color: Colors.black, child: video),
            ),
          ),
        );

      case PortraitLayoutMode.immersive:
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: ColoredBox(color: Colors.black, child: video),
        );

      case PortraitLayoutMode.compatibility:
        return _buildCompatibilityVideo(constraints, maxHeight: maxHeight);
    }
  }

  Widget _buildCompatibilityVideo(BoxConstraints constraints, {double? maxHeight}) {
    final player = GlobalPlayerService.instance.player;

    return StreamBuilder<List<int?>>(
      stream: CombineLatestStream.list([player.width, player.height]),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final videoWidth = data != null && data.isNotEmpty ? data[0] : null;
        final videoHeight = data != null && data.length > 1 ? data[1] : null;

        final aspectRatio = _resolveAspectRatio(videoWidth, videoHeight);

        final width = constraints.maxWidth;

        if (!constraints.hasBoundedHeight) {
          return SizedBox(
            width: width,
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: ColoredBox(color: Colors.black, child: video),
            ),
          );
        }

        final panelmaxHeight = constraints.maxHeight * 0.6;
        final calculatedHeight = width / aspectRatio;
        final naturalHeight = calculatedHeight > panelmaxHeight ? panelmaxHeight : calculatedHeight;
        final height = maxHeight == null ? naturalHeight : math.min(naturalHeight, maxHeight);

        return SizedBox(
          width: width,
          height: height,
          child: ColoredBox(color: Colors.black, child: video),
        );
      },
    );
  }

  double _resolveAspectRatio(int? width, int? height) => resolveLivePlayAspectRatio(width, height);
}

class LivePlayContent extends StatelessWidget {
  const LivePlayContent({
    super.key,
    required this.controller,
    required this.isInPip,
    required this.mode,
  });

  final LivePlayController controller;
  final bool isInPip;
  final VideoMode mode;

  @override
  Widget build(BuildContext context) {
    final player = GlobalPlayerService.instance.player;

    if (isInPip) {
      return Theme(
        data: ThemeData.dark(),
        child: Container(
          key: const ValueKey('pip'),
          color: Colors.transparent,
          child: player.buildPiPOverlay(),
        ),
      );
    }

    if (mode == VideoMode.normal) {
      return _buildNormalContent(context);
    }

    return ColoredBox(
      color: Colors.black,
      child: LivePlayVideo(controller: controller, expandToParent: true),
    );
  }

  Widget _buildNormalContent(BuildContext context) {
    final layoutMode = SettingsService.to.player.portraitLayoutMode;

    if (layoutMode == PortraitLayoutMode.immersive) {
      return _buildImmersiveLayout(context);
    }

    return _buildNormalLayout(context, layoutMode: layoutMode);
  }

  Widget _buildNormalLayout(BuildContext context, {required PortraitLayoutMode layoutMode}) {
    final compactHeader = MediaQuery.sizeOf(context).width < 600;
    final wideWindow = MediaQuery.sizeOf(context).width > livePlayPortraitStackMaxWidth;
    final player = GlobalPlayerService.instance.player;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: LivePlayHeader(controller: controller, compactHeader: compactHeader),
      body: StreamBuilder<List<int?>>(
        stream: CombineLatestStream.list([player.width, player.height]),
        builder: (context, snapshot) {
          final frames = snapshot.data;
          final aspectRatio = resolveLivePlayAspectRatio(
            frames != null && frames.isNotEmpty ? frames[0] : null,
            frames != null && frames.length > 1 ? frames[1] : null,
          );
          return LivePlayLayout(
            layoutMode: layoutMode,
            isPortraitSource: aspectRatio < 1,
            sourceAspectRatio: aspectRatio,
            splitBySourceOrientation: PlatformUtils.isAndroid,
            danmakuPanelHeight: wideWindow
                ? SettingsService.to.player.innerScreenDanmakuHeight.v
                : SettingsService.to.player.outerScreenDanmakuHeight.v,
            // A wide window owns its video box too: both topologies lay the
            // surface out from the source aspect, so it has to fill the box
            // instead of adding its own 16:9 frame.
            video: LivePlayVideo(
              controller: controller,
              expandToParent: controller.site == Sites.iptvSite || wideWindow,
            ),
            resolution: const ResolutionsRow(),
            danmaku: _buildDanmakuContent(),
            showPanel: controller.site != Sites.iptvSite,
          );
        },
      ),
    );
  }

  Widget _buildImmersiveLayout(BuildContext context) {
    final compactHeader = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: LivePlayHeader(controller: controller, compactHeader: compactHeader),
      body: LivePlayShell(controller: controller, showPanel: controller.site != Sites.iptvSite),
    );
  }

  Widget _buildDanmakuContent() {
    return Obx(() {
      final state = controller.state.value;

      if (!state.room.success) {
        return const SizedBox.shrink();
      }

      if (controller.site == Sites.iptvSite) {
        return const SizedBox.shrink();
      }

      final globalState = GlobalPlayerState.to;

      if (globalState.isFullscreen.value || globalState.isWindowFullscreen.value) {
        return const SizedBox.shrink();
      }

      return const DanmakuTabView();
    });
  }
}
