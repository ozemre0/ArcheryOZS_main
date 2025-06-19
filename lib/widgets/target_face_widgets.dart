import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'dart:math' as math;

class TargetFaceWidget extends StatelessWidget {
  final String targetType;
  final double size;
  final bool isSelected;

  const TargetFaceWidget({
    super.key,
    required this.targetType,
    this.size = 80,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(
        painter: targetType == '80cm' 
          ? Target80cmPainter() 
          : Target122cmPainter(),
        size: Size(size, size),
      ),
    );
  }
}

// Interactive Target Face Widget for scoring - Direct on-screen scoring
class InteractiveTargetFaceWidget extends StatefulWidget {
  final String targetType;
  final double size;
  final Function(int score) onScoreTap;
  final int? arrowsPerSeries;
  final List<int>? existingArrows; // Geçmiş ok skorları
  final bool isInteractive; // Dokunma aktif mi

  const InteractiveTargetFaceWidget({
    super.key,
    required this.targetType,
    required this.size,
    required this.onScoreTap,
    this.arrowsPerSeries,
    this.existingArrows,
    this.isInteractive = true,
  });

  @override
  State<InteractiveTargetFaceWidget> createState() => _InteractiveTargetFaceWidgetState();
}

class _InteractiveTargetFaceWidgetState extends State<InteractiveTargetFaceWidget> {
  List<ArrowHole> arrowHoles = [];
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  bool _isAutoZoomed = false;
  int _currentArrowCount = 0;
  
  // Drag ve preview için
  bool _isDragging = false;
  Offset? _currentDragPosition;
  int? _previewScore;

  @override
  void initState() {
    super.initState();
    _loadExistingArrows();
  }

  @override
  void didUpdateWidget(InteractiveTargetFaceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.existingArrows != oldWidget.existingArrows) {
      _loadExistingArrows();
    }
  }

  void _loadExistingArrows() {
    if (widget.existingArrows != null) {
      arrowHoles.clear();
      _currentArrowCount = widget.existingArrows!.length;
      
      // Geçmiş okları rastgele pozisyonlarda göster (görsel amaçlı)
      final center = Offset(widget.size / 2, widget.size / 2);
      final radius = widget.size / 2;
      
      for (int i = 0; i < widget.existingArrows!.length; i++) {
        final score = widget.existingArrows![i];
        final isXRing = score == -1; // ScoringRules.xScoreInternal
        final displayScore = isXRing ? 10 : score;
        
        // Skora göre pozisyon belirle (yüksek skor merkeze yakın)
        double targetRadius;
        if (widget.targetType == '80cm') {
          targetRadius = (radius / 6) * (6 - (displayScore - 5).clamp(0, 5));
        } else {
          targetRadius = (radius / 10) * (10 - (displayScore - 1).clamp(0, 9));
        }
        
        // Rastgele açı
        final angle = (i * 60.0 + (i * 23.0)) * (3.14159 / 180.0); // Dağıtılmış açılar
        final randomRadius = targetRadius * (0.3 + (i % 3) * 0.2); // Varyasyon
        
        final position = Offset(
          center.dx + randomRadius * math.cos(angle),
          center.dy + randomRadius * math.sin(angle),
        );
        
        arrowHoles.add(ArrowHole(
          position: position,
          score: displayScore,
          isXRing: isXRing,
        ));
      }
      
      if (mounted) {
        setState(() {});
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
              child: ClipOval(
        child: GestureDetector(
          onPanStart: widget.isInteractive ? (details) {
            // Basılı tutma başlangıcı - zoom yap
            if (!_isAutoZoomed) {
              _autoZoomToPosition(details.localPosition);
            }
            // Drag pozisyonuna göre skor hesapla
            final dragTargetPosition = _transformPosition(details.localPosition);
            setState(() {
              _isDragging = true;
              _currentDragPosition = details.localPosition;
              _previewScore = _calculateScore(dragTargetPosition);
            });
          } : null,
          onPanUpdate: widget.isInteractive ? (details) {
            // Sürükleme sırasında pozisyon güncelle - Drag pozisyonuna göre
            final dragTargetPosition = _transformPosition(details.localPosition);
            setState(() {
              _currentDragPosition = details.localPosition;
              _previewScore = _calculateScore(dragTargetPosition);
            });
          } : null,
          onPanEnd: widget.isInteractive ? (details) {
            // Bırakınca ok deliği oluştur - Drag pozisyonunda
            final dragTargetPosition = _transformPosition(details.localPosition);
            final score = _calculateScore(dragTargetPosition);
            
            // Debug: Önizleme skoru ile karşılaştır
            print('Preview Score: $_previewScore, Final Score: $score');
            
            if (score > 0) {
              final isXRing = _isXRing(dragTargetPosition);
              
              setState(() {
                // Ok deliği drag pozisyonunda
                arrowHoles.add(ArrowHole(
                  position: dragTargetPosition, // Drag pozisyonu
                  score: score,
                  isXRing: isXRing,
                ));
                _currentArrowCount++;
              });
              
              // X ring ise -1 gönder (ScoringRules.xScoreInternal)
              final scoreToSend = isXRing ? -1 : score;
              widget.onScoreTap(scoreToSend);
            }
            
            // Drag bitir ve zoom out
            setState(() {
              _isDragging = false;
              _currentDragPosition = null;
              _previewScore = null;
            });
            
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted) {
                setState(() {
                  _scale = 1.0;
                  _offset = Offset.zero;
                  _isAutoZoomed = false;
                });
              }
            });
          } : null,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..scale(_scale)
              ..translate(_offset.dx / _scale, _offset.dy / _scale),
            child: Stack(
              children: [
                // Target face
                CustomPaint(
                  painter: widget.targetType == '80cm' 
                    ? Target80cmPainter() 
                    : Target122cmPainter(),
                  size: Size(widget.size, widget.size),
                ),
                // Arrow holes
                ...arrowHoles.map((hole) => _buildArrowHole(hole)),
                // Crosshair
                CustomPaint(
                  painter: CrosshairPainter(),
                  size: Size(widget.size, widget.size),
                ),
                // Skor önizleme (drag sırasında)
                if (_isDragging && _previewScore != null && _currentDragPosition != null)
                  _buildScorePreview(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _autoZoomToPosition(Offset position) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final distanceFromCenter = (position - center).distance;
    final maxDistance = widget.size / 2;
    final normalizedDistance = (distanceFromCenter / maxDistance).clamp(0.0, 1.0);
    
    // %20 daha az zoom - Higher zoom for center, lower for edges
    final targetZoom = (2.5 - (normalizedDistance * 1.0)) * 0.8; // 2.0x to 1.2x zoom
    
    setState(() {
      _scale = targetZoom;
      _offset = _calculateOffsetForPosition(position, targetZoom);
      _isAutoZoomed = true;
    });
  }

  Offset _calculateOffsetForPosition(Offset position, double zoom) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final targetOffset = (center - position) * (zoom - 1);
    return _constrainOffset(targetOffset);
  }

  Offset _constrainOffset(Offset offset) {
    final maxOffset = (widget.size * (_scale - 1)) / 2;
    return Offset(
      offset.dx.clamp(-maxOffset, maxOffset),
      offset.dy.clamp(-maxOffset, maxOffset),
    );
  }



  Offset _transformPosition(Offset screenPosition) {
    // Convert screen position to target position considering scale and offset
    final center = Offset(widget.size / 2, widget.size / 2);
    
    // Transform hesaplaması: screen -> target koordinatları
    // 1. Merkeze göre normalize et
    final normalizedPos = screenPosition - center;
    // 2. Scale'i tersine çevir
    final unscaledPos = normalizedPos / _scale;
    // 3. Offset'i tersine çevir
    final offsetCorrectedPos = unscaledPos - Offset(_offset.dx / _scale, _offset.dy / _scale);
    // 4. Merkezi geri ekle
    final targetPos = offsetCorrectedPos + center;
    
    return targetPos;
  }

  int _calculateScore(Offset position) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final distance = (position - center).distance;
    final radius = widget.size / 2;
    
    if (widget.targetType == '80cm') {
      // 80cm target: 6 rings - İçten dışa: 10(X), 9, 8, 7, 6, 5
      final ringSize = radius / 6;
      
      // Her ring için net sınırlar (overlap yok)
      if (distance <= ringSize) return 10; // 1. ring (10 ve X)
      if (distance <= ringSize * 2) return 9; // 2. ring
      if (distance <= ringSize * 3) return 8; // 3. ring
      if (distance <= ringSize * 4) return 7; // 4. ring
      if (distance <= ringSize * 5) return 6; // 5. ring
      if (distance <= ringSize * 6) return 5; // 6. ring
    } else {
      // 122cm target: 10 rings - İçten dışa: 10(X), 9, 8, 7, 6, 5, 4, 3, 2, 1
      final ringSize = radius / 10;
      
      // Her ring için net sınırlar (overlap yok)
      if (distance <= ringSize) return 10; // 1. ring (10 ve X)
      if (distance <= ringSize * 2) return 9; // 2. ring
      if (distance <= ringSize * 3) return 8; // 3. ring
      if (distance <= ringSize * 4) return 7; // 4. ring
      if (distance <= ringSize * 5) return 6; // 5. ring
      if (distance <= ringSize * 6) return 5; // 6. ring
      if (distance <= ringSize * 7) return 4; // 7. ring
      if (distance <= ringSize * 8) return 3; // 8. ring
      if (distance <= ringSize * 9) return 2; // 9. ring
      if (distance <= ringSize * 10) return 1; // 10. ring
    }
    
    return 0; // Miss
  }

  bool _isXRing(Offset position) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final distance = (position - center).distance;
    final radius = widget.size / 2;
    
    // X ring is the inner part of the 10 ring
    final xRingSize = (radius / (widget.targetType == '80cm' ? 6 : 10)) * 0.5;
    return distance <= xRingSize;
  }

  Widget _buildArrowHole(ArrowHole hole) {
    return Positioned(
      left: hole.position.dx - 3.5,
      top: hole.position.dy - 3.5,
      child: Container(
        width: 7,  // %40 küçük (12 * 0.6 = 7.2 ≈ 7)
        height: 7, // %40 küçük
        decoration: BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 0.5),
        ),
      ),
    );
  }

  Widget _buildScorePreview() {
    if (_currentDragPosition == null || _previewScore == null) {
      return const SizedBox.shrink();
    }

    // Drag pozisyonuna göre X ring kontrolü
    final dragTargetPosition = _transformPosition(_currentDragPosition!);
    final isXRing = _isXRing(dragTargetPosition);

    return Positioned(
      left: _currentDragPosition!.dx - 3.5, // Drag pozisyonunda
      top: _currentDragPosition!.dy - 35, // Drag pozisyonunun üstünde
      child: Column(
        children: [
          // Skor gösterimi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white, width: 0.5),
            ),
            child: Text(
              _previewScore == 10 && isXRing ? 'X' : _previewScore.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Ok deliği önizlemesi
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.8), // Kırmızı önizleme
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// Series Target Scoring Dialog for complete series input
class SeriesTargetScoringDialog extends StatefulWidget {
  final String targetType;
  final int arrowsPerSeries;
  final Function(List<int> scores) onSeriesComplete;

  const SeriesTargetScoringDialog({
    super.key,
    required this.targetType,
    required this.arrowsPerSeries,
    required this.onSeriesComplete,
  });

  @override
  State<SeriesTargetScoringDialog> createState() => _SeriesTargetScoringDialogState();
}

class _SeriesTargetScoringDialogState extends State<SeriesTargetScoringDialog> {
  List<int> seriesScores = [];
  List<bool> seriesXRings = []; // Track which arrows are X rings
  int currentArrow = 0;

  int get arrowsPerSeries => widget.arrowsPerSeries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isSeriesComplete = seriesScores.length >= arrowsPerSeries;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(10),
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            // Header with arrow count
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.targetFaceScoring,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    l10n.arrowCount(seriesScores.length + 1, arrowsPerSeries),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            
            // Current series scores display
            if (seriesScores.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: seriesScores.asMap().entries.map((entry) {
                      final index = entry.key;
                      final score = entry.value;
                      return Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: _getColorForScore(score),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black26),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          score == 10 && _isXRing(entry.key) ? 'X' : score.toString(),
                          style: TextStyle(
                            color: _getTextColorForScore(score),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            
            // Instructions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                isSeriesComplete 
                  ? l10n.seriesComplete
                  : l10n.tapToEnterScore,
                style: TextStyle(
                  fontSize: 14,
                  color: isSeriesComplete 
                    ? Colors.green 
                    : Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            // Target face or completion buttons
            Expanded(
              child: isSeriesComplete
                ? _buildCompletionButtons(context, l10n)
                : InteractiveZoomedTargetWidget(
                    targetType: widget.targetType,
                    onScoreTap: (score) {
                      // We need to get X ring info from the target widget
                      // For now, we'll determine X ring based on the last arrow hole
                      setState(() {
                        seriesScores.add(score);
                        // This is a simplified approach - we'll track X rings properly
                        seriesXRings.add(false); // Will be updated with proper X ring detection
                      });
                    },
                  ),
            ),
            
            // Bottom actions
            if (!isSeriesComplete)
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (seriesScores.isNotEmpty)
                      Expanded(
                        child: ElevatedButton.icon(
                                                  onPressed: () {
                          setState(() {
                            seriesScores.removeLast();
                            if (seriesXRings.isNotEmpty) {
                              seriesXRings.removeLast();
                            }
                          });
                        },
                          icon: const Icon(Icons.undo),
                          label: Text(l10n.undoButton),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    if (seriesScores.isNotEmpty) const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        label: Text(l10n.cancel),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionButtons(BuildContext context, AppLocalizations l10n) {
    final totalScore = seriesScores.fold(0, (sum, score) => sum + (score == 11 ? 10 : score));
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle,
            size: 80,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
                    Text(
            l10n.seriesComplete,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${l10n.total}: $totalScore/${arrowsPerSeries * 10}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ortalama: ${(totalScore / arrowsPerSeries).toStringAsFixed(1)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    seriesScores.clear();
                    seriesXRings.clear();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: Text(l10n.reset),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  widget.onSeriesComplete(seriesScores);
                  // Seri tamamlandıktan sonra dialog'u kapat ve yeni seri başlat
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.check),
                label: Text(l10n.nextSeries),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getColorForScore(int score) {
    if (score == 11 || score == 10) return Colors.yellow;
    if (score == 9) return Colors.yellow;
    if (score == 8 || score == 7) return Colors.red;
    if (score == 6 || score == 5) return Colors.blue;
    if (score == 4 || score == 3) return Colors.black;
    if (score == 2 || score == 1) return Colors.white;
    return Colors.grey;
  }

  Color _getTextColorForScore(int score) {
    if (score == 4 || score == 3) return Colors.white;
    if (score == 2 || score == 1) return Colors.black;
    return Colors.black;
  }
  
  bool _isXRing(int arrowIndex) {
    if (arrowIndex < seriesXRings.length) {
      return seriesXRings[arrowIndex];
    }
    return false;
  }
}

// Interactive Zoomed Target Widget with zoom, pan and drag
class InteractiveZoomedTargetWidget extends StatefulWidget {
  final String targetType;
  final Function(int score) onScoreTap;

  const InteractiveZoomedTargetWidget({
    super.key,
    required this.targetType,
    required this.onScoreTap,
  });

  @override
  State<InteractiveZoomedTargetWidget> createState() => _InteractiveZoomedTargetWidgetState();
}

class _InteractiveZoomedTargetWidgetState extends State<InteractiveZoomedTargetWidget> with TickerProviderStateMixin {
  List<ArrowHole> arrowHoles = [];
  double _scale = 1.0;
  double _previousScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _previousOffset = Offset.zero;
  
  // Crosshair position for precise aiming
  Offset? _crosshairPosition;
  bool _showCrosshair = false;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final targetSize = math.min(screenSize.width, screenSize.height) * 0.8;
    
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        children: [
          // Target face with zoom and pan
          GestureDetector(
            onScaleStart: (details) {
              _previousScale = _scale;
              _previousOffset = _offset;
              setState(() {
                _showCrosshair = true;
                _crosshairPosition = details.localFocalPoint;
              });
              
              // Auto zoom to the touch position for better aiming
              _autoZoomToPosition(details.localFocalPoint, targetSize);
            },
            onScaleUpdate: (details) {
              setState(() {
                // If scale is changing (pinch gesture)
                if (details.scale != 1.0) {
                  _scale = (_previousScale * details.scale).clamp(1.0, 4.0);
                }
                
                // Calculate new offset with bounds checking
                final newOffset = _previousOffset + details.focalPointDelta;
                final maxOffset = targetSize * (_scale - 1) / 2;
                
                _offset = Offset(
                  newOffset.dx.clamp(-maxOffset, maxOffset),
                  newOffset.dy.clamp(-maxOffset, maxOffset),
                );
                
                _crosshairPosition = details.localFocalPoint;
              });
            },
            onScaleEnd: (details) {
              // Check if it was a tap (no scale change and minimal movement)
              if (details.velocity.pixelsPerSecond.distance < 50 && 
                  (_scale - _previousScale).abs() < 0.1 &&
                  _crosshairPosition != null) {
                _handleTap(_crosshairPosition!, targetSize);
              }
              
              setState(() {
                _showCrosshair = false;
              });
            },
            child: Center(
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translate(_offset.dx, _offset.dy)
                  ..scale(_scale),
                child: Container(
                  width: targetSize,
                  height: targetSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    painter: ZoomedTargetPainter(
                      targetType: widget.targetType,
                      arrowHoles: arrowHoles,
                    ),
                    size: Size(targetSize, targetSize),
                  ),
                ),
              ),
            ),
          ),
          
          // Crosshair overlay
          if (_showCrosshair && _crosshairPosition != null)
            Positioned(
              left: _crosshairPosition!.dx - 15,
              top: _crosshairPosition!.dy - 15,
              child: IgnorePointer(
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.red, width: 2),
                    shape: BoxShape.circle,
                  ),
                  child: CustomPaint(
                    painter: CrosshairPainter(),
                  ),
                ),
              ),
            ),
          
          // Zoom controls
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: "zoom_in",
                  onPressed: () {
                    final newScale = (_scale * 1.2).clamp(1.0, 4.0);
                    _animateToZoomAndOffset(newScale, _offset);
                  },
                  child: const Icon(Icons.zoom_in),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: "zoom_out",
                  onPressed: () {
                    final newScale = (_scale / 1.2).clamp(1.0, 4.0);
                    final newOffset = newScale == 1.0 ? Offset.zero : _offset;
                    _animateToZoomAndOffset(newScale, newOffset);
                  },
                  child: const Icon(Icons.zoom_out),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: "reset_view",
                  onPressed: () {
                    _animateToZoomAndOffset(1.0, Offset.zero);
                  },
                  child: const Icon(Icons.center_focus_strong),
                ),
              ],
            ),
          ),
          
          // Instructions overlay
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Dokunduğunuzda otomatik zoom • Puan girmek için dokunun',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void _handleTap(Offset position, double targetSize) {
    // Convert screen position to target position considering zoom and pan
    final center = Offset(targetSize / 2, targetSize / 2);
    final transformedCenter = Offset(
      center.dx * _scale + _offset.dx,
      center.dy * _scale + _offset.dy,
    );
    
    // Calculate relative position on the target
    final relativePosition = Offset(
      (position.dx - transformedCenter.dx) / _scale + center.dx,
      (position.dy - transformedCenter.dy) / _scale + center.dy,
    );
    
    final result = _calculateScoreAndXRing(relativePosition, targetSize, widget.targetType);
    final score = result['score'];
    final isXRing = result['isXRing'];
    
    // Add arrow hole at the correct position
    setState(() {
      arrowHoles.add(ArrowHole(
        position: relativePosition,
        score: score,
        isXRing: isXRing,
      ));
      _showCrosshair = false;
    });
    
    // Call the callback after a short delay to show the hole
    Future.delayed(const Duration(milliseconds: 500), () {
      widget.onScoreTap(score);
    });
  }
  
  void _autoZoomToPosition(Offset touchPosition, double targetSize) {
    // Convert screen position to target position
    final center = Offset(targetSize / 2, targetSize / 2);
    final screenCenter = Offset(
      MediaQuery.of(context).size.width / 2,
      MediaQuery.of(context).size.height / 2,
    );
    
    // Calculate relative position on the target
    final relativePosition = Offset(
      (touchPosition.dx - screenCenter.dx) / _scale + center.dx,
      (touchPosition.dy - screenCenter.dy) / _scale + center.dy,
    );
    
    final distance = (relativePosition - center).distance;
    final radius = targetSize / 2;
    final normalizedDistance = distance / radius;
    
    // Determine zoom level based on touch position
    double targetZoom = 2.5; // Default zoom for aiming
    
    // Higher zoom for center area (more precision needed)
    if (normalizedDistance <= 0.2) {
      targetZoom = 3.5; // High zoom for center shots
    } else if (normalizedDistance <= 0.5) {
      targetZoom = 3.0; // Medium-high zoom for middle rings
    } else if (normalizedDistance <= 0.8) {
      targetZoom = 2.5; // Medium zoom for outer rings
    } else {
      targetZoom = 2.0; // Lower zoom for edge shots
    }
    
    // Calculate offset to center the touch position
    final targetOffset = Offset(
      (center.dx - relativePosition.dx) * targetZoom,
      (center.dy - relativePosition.dy) * targetZoom,
    );
    
    // Animate to the new zoom and position
    _animateToZoomAndOffset(targetZoom, targetOffset);
  }
  
  void _animateToZoomAndOffset(double targetZoom, Offset targetOffset) {
    const duration = Duration(milliseconds: 400); // 2x faster
    const curve = Curves.easeInOut;
    
    final startZoom = _scale;
    final startOffset = _offset;
    
    // Create animation controller if not exists
    late AnimationController animationController;
    animationController = AnimationController(
      duration: duration,
      vsync: this,
    );
    
    final animation = CurvedAnimation(
      parent: animationController,
      curve: curve,
    );
    
    animation.addListener(() {
      setState(() {
        _scale = startZoom + (targetZoom - startZoom) * animation.value;
        _offset = Offset(
          startOffset.dx + (targetOffset.dx - startOffset.dx) * animation.value,
          startOffset.dy + (targetOffset.dy - startOffset.dy) * animation.value,
        );
      });
    });
    
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        animationController.dispose();
      }
    });
    
    animationController.forward();
  }

  Map<String, dynamic> _calculateScoreAndXRing(Offset tapPosition, double targetSize, String targetType) {
    final center = Offset(targetSize / 2, targetSize / 2);
    final distance = (tapPosition - center).distance;
    final radius = targetSize / 2;
    
    // Normalize distance (0.0 = center, 1.0 = edge)
    final normalizedDistance = distance / radius;
    
    bool isXRing = false;
    int score = 0;
    
    if (targetType == '80cm') {
      score = _calculate80cmScore(normalizedDistance);
      isXRing = normalizedDistance <= 0.08 && score == 10; // X ring check
    } else {
      score = _calculate122cmScore(normalizedDistance);
      isXRing = normalizedDistance <= 0.05 && score == 10; // X ring check
    }
    
    return {'score': score, 'isXRing': isXRing};
  }
  
  int _calculateScore(Offset tapPosition, double targetSize, String targetType) {
    final result = _calculateScoreAndXRing(tapPosition, targetSize, targetType);
    return result['score'];
  }

  int _calculate80cmScore(double normalizedDistance) {
    // 80cm target has 6 rings (5-10 + X) - from center outward
    if (normalizedDistance > 1.0) return 0; // Miss
    
    // X ring (innermost) - same as 10 points
    if (normalizedDistance <= 0.08) return 10; // X = 10 points (same as 10 ring)
    
    // 10 ring (inner gold)
    if (normalizedDistance <= 0.167) return 10; // 1/6 of radius
    
    // 9 ring (outer gold)
    if (normalizedDistance <= 0.333) return 9; // 2/6 of radius
    
    // 8 ring (inner red)
    if (normalizedDistance <= 0.5) return 8; // 3/6 of radius
    
    // 7 ring (outer red)
    if (normalizedDistance <= 0.667) return 7; // 4/6 of radius
    
    // 6 ring (inner blue)
    if (normalizedDistance <= 0.833) return 6; // 5/6 of radius
    
    // 5 ring (outer blue - outermost)
    if (normalizedDistance <= 1.0) return 5;
    
    return 0; // Miss
  }

  int _calculate122cmScore(double normalizedDistance) {
    // 122cm target has 10 rings (1-10 + X) - from center outward
    if (normalizedDistance > 1.0) return 0; // Miss
    
    // X ring (innermost) - same as 10 points
    if (normalizedDistance <= 0.05) return 10; // X = 10 points (same as 10 ring)
    
    // 10 ring (inner gold)
    if (normalizedDistance <= 0.1) return 10; // 1/10 of radius
    
    // 9 ring (outer gold)
    if (normalizedDistance <= 0.2) return 9; // 2/10 of radius
    
    // 8 ring (inner red)
    if (normalizedDistance <= 0.3) return 8; // 3/10 of radius
    
    // 7 ring (outer red)
    if (normalizedDistance <= 0.4) return 7; // 4/10 of radius
    
    // 6 ring (inner blue)
    if (normalizedDistance <= 0.5) return 6; // 5/10 of radius
    
    // 5 ring (outer blue)
    if (normalizedDistance <= 0.6) return 5; // 6/10 of radius
    
    // 4 ring (inner black)
    if (normalizedDistance <= 0.7) return 4; // 7/10 of radius
    
    // 3 ring (outer black)
    if (normalizedDistance <= 0.8) return 3; // 8/10 of radius
    
    // 2 ring (inner white)
    if (normalizedDistance <= 0.9) return 2; // 9/10 of radius
    
    // 1 ring (outer white - outermost)
    if (normalizedDistance <= 1.0) return 1;
    
    return 0; // Miss
  }
}

// Arrow hole data class
class ArrowHole {
  final Offset position;
  final int score;
  final bool isXRing;

  ArrowHole({
    required this.position,
    required this.score,
    this.isXRing = false,
  });
}

// Zoomed Target Painter with arrow holes
class ZoomedTargetPainter extends CustomPainter {
  final String targetType;
  final List<ArrowHole> arrowHoles;

  ZoomedTargetPainter({
    required this.targetType,
    required this.arrowHoles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the target face first
    if (targetType == '80cm') {
      _paint80cmTarget(canvas, size);
    } else {
      _paint122cmTarget(canvas, size);
    }
    
    // Draw arrow holes on top
    _paintArrowHoles(canvas, size);
  }

  void _paint80cmTarget(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Ring colors (from outside to inside) - FITA 80cm standard
    final colors = [
      Colors.blue,       // 5-6 rings (dış mavi)
      Colors.red,        // 7-8 rings (orta kırmızı)
      Colors.yellow,     // 9-10 rings (iç sarı/altın)
    ];
    
    // Draw rings (6 rings total for 80cm target - 2-2-2 pattern)
    for (int i = 0; i < 6; i++) {
      final ringRadius = radius * (6 - i) / 6;
      final colorIndex = i ~/ 2; // Her 2 ring aynı renk (2-2-2 pattern)
      
      final paint = Paint()
        ..color = colors[colorIndex]
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(center, ringRadius, paint);
      
      // Ring borders
      final borderPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      
      canvas.drawCircle(center, ringRadius, borderPaint);
    }
    
    // Inner ring divisions (scoring lines between same color rings)
    for (int i = 1; i < 6; i++) {
      final ringRadius = radius * (6 - i) / 6;
      final divisionPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      
      canvas.drawCircle(center, ringRadius, divisionPaint);
    }
    
    // X Ring (inner gold ring) - 10 puanın içinde
    final xRingRadius = radius * 0.08;
    final xRingPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, xRingRadius, xRingPaint);
    
    // X Ring border
    final xRingBorderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    canvas.drawCircle(center, xRingRadius, xRingBorderPaint);
    
    // Center cross lines
    final crossPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2;
    
    // Vertical line
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.12),
      Offset(center.dx, center.dy + radius * 0.12),
      crossPaint,
    );
    
    // Horizontal line
    canvas.drawLine(
      Offset(center.dx - radius * 0.12, center.dy),
      Offset(center.dx + radius * 0.12, center.dy),
      crossPaint,
    );
  }

  void _paint122cmTarget(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Ring colors (from outside to inside) - FITA 122cm standard
    final colors = [
      Colors.white,      // 1-2 rings
      Colors.black,      // 3-4 rings  
      Colors.blue,       // 5-6 rings
      Colors.red,        // 7-8 rings
      Colors.yellow,     // 9-10 rings (gold)
    ];
    
    // Draw rings (10 rings total for 122cm target)
    for (int i = 0; i < 10; i++) {
      final ringRadius = radius * (10 - i) / 10;
      final colorIndex = i ~/ 2; // Her 2 ring aynı renk (FITA kuralı)
      
      final paint = Paint()
        ..color = colors[colorIndex]
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(center, ringRadius, paint);
      
      // Ring borders
      final borderPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      
      canvas.drawCircle(center, ringRadius, borderPaint);
    }
    
    // X Ring (inner gold ring) - 10 puanın içinde
    final xRingRadius = radius * 0.05;
    final xRingPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, xRingRadius, xRingPaint);
    
    // X Ring border
    final xRingBorderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    canvas.drawCircle(center, xRingRadius, xRingBorderPaint);
    
    // Inner ring divisions (scoring lines between same color rings)
    for (int i = 1; i < 10; i++) {
      final ringRadius = radius * (10 - i) / 10;
      final divisionPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      
      canvas.drawCircle(center, ringRadius, divisionPaint);
    }
    
    // Center cross lines
    final crossPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2;
    
    // Vertical line
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.08),
      Offset(center.dx, center.dy + radius * 0.08),
      crossPaint,
    );
    
    // Horizontal line
    canvas.drawLine(
      Offset(center.dx - radius * 0.08, center.dy),
      Offset(center.dx + radius * 0.08, center.dy),
      crossPaint,
    );
  }

  void _paintArrowHoles(Canvas canvas, Size size) {
    for (final hole in arrowHoles) {
      // Draw arrow hole (black circle with white border)
      final holePaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;
      
      final holeBorderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      
      canvas.drawCircle(hole.position, 8, holePaint);
      canvas.drawCircle(hole.position, 8, holeBorderPaint);
      
      // Draw score text next to the hole
      final textPainter = TextPainter(
        text: TextSpan(
          text: hole.isXRing ? 'X' : hole.score.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          hole.position.dx + 12,
          hole.position.dy - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Crosshair Painter for precise aiming
class CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    
    // Vertical line
    canvas.drawLine(
      Offset(center.dx, 2),
      Offset(center.dx, size.height - 2),
      paint,
    );
    
    // Horizontal line
    canvas.drawLine(
      Offset(2, center.dy),
      Offset(size.width - 2, center.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// 80cm FITA Target (6 Rings)
class Target80cmPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Ring colors (from outside to inside) - FITA 80cm standard
    final colors = [
      Colors.blue,       // 5-6 rings (dış mavi)
      Colors.red,        // 7-8 rings (orta kırmızı)
      Colors.yellow,     // 9-10 rings (iç sarı/altın)
    ];
    
    // Draw rings (6 rings total for 80cm target - 2-2-2 pattern)
    for (int i = 0; i < 6; i++) {
      final ringRadius = radius * (6 - i) / 6;
      final colorIndex = i ~/ 2; // Her 2 ring aynı renk (2-2-2 pattern)
      
      final paint = Paint()
        ..color = colors[colorIndex]
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(center, ringRadius, paint);
      
      // Ring borders
      final borderPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      
      canvas.drawCircle(center, ringRadius, borderPaint);
    }
    
    // Inner ring divisions (scoring lines between same color rings)
    for (int i = 1; i < 6; i++) {
      final ringRadius = radius * (6 - i) / 6;
      final divisionPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      
      canvas.drawCircle(center, ringRadius, divisionPaint);
    }
    
    // X Ring (inner gold ring) - 10 puanın içinde
    final xRingRadius = radius * 0.08; // 10 ring'in yarısı kadar
    final xRingPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, xRingRadius, xRingPaint);
    
    // X Ring border
    final xRingBorderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    
    canvas.drawCircle(center, xRingRadius, xRingBorderPaint);
    
    // Center cross lines
    final crossPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.2;
    
    // Vertical line
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.12),
      Offset(center.dx, center.dy + radius * 0.12),
      crossPaint,
    );
    
    // Horizontal line
    canvas.drawLine(
      Offset(center.dx - radius * 0.12, center.dy),
      Offset(center.dx + radius * 0.12, center.dy),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// 122cm FITA Target (10 Rings + X Ring)
class Target122cmPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Ring colors (from outside to inside) - FITA 122cm standard
    final colors = [
      Colors.white,      // 1-2 rings
      Colors.black,      // 3-4 rings  
      Colors.blue,       // 5-6 rings
      Colors.red,        // 7-8 rings
      Colors.yellow,     // 9-10 rings (gold)
    ];
    
    // Draw rings (10 rings total for 122cm target)
    for (int i = 0; i < 10; i++) {
      final ringRadius = radius * (10 - i) / 10;
      final colorIndex = i ~/ 2; // Her 2 ring aynı renk (FITA kuralı)
      
      final paint = Paint()
        ..color = colors[colorIndex]
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(center, ringRadius, paint);
      
      // Ring borders
      final borderPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      
      canvas.drawCircle(center, ringRadius, borderPaint);
    }
    
    // X Ring (inner gold ring) - 10 puanın içinde
    final xRingRadius = radius * 0.05; // 10 ring'in yarısı kadar
    final xRingPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, xRingRadius, xRingPaint);
    
    // X Ring border
    final xRingBorderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    
    canvas.drawCircle(center, xRingRadius, xRingBorderPaint);
    
    // Inner ring divisions (scoring lines between same color rings)
    for (int i = 1; i < 10; i++) {
      final ringRadius = radius * (10 - i) / 10;
      final divisionPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      
      canvas.drawCircle(center, ringRadius, divisionPaint);
    }
    
    // Center cross lines
    final crossPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1;
    
    // Vertical line
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.08),
      Offset(center.dx, center.dy + radius * 0.08),
      crossPaint,
    );
    
    // Horizontal line
    canvas.drawLine(
      Offset(center.dx - radius * 0.08, center.dy),
      Offset(center.dx + radius * 0.08, center.dy),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
} 