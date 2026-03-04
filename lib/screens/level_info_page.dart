import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/country_scope.dart';
import '../services/level_service.dart';

/// 포인트 숫자 포맷 (천 단위 콤마)
String _formatPoints(int n) {
  if (n < 1000) return '$n';
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// 레벨 배지 색 (1: 회색, 2~29: 그라데이션, 30: 골드)
Color _levelColor(int level) {
  if (level >= 30) return const Color(0xFFD4AF37);
  if (level == 1) return const Color(0xFF9E9E9E);
  final t = (level - 1) / 28;
  return Color.lerp(const Color(0xFF9E9E9E), const Color(0xFF26A69A), t)!;
}

/// 레벨 정보 (회원레벨 안내) - 사진 참고 스타일
class LevelInfoPage extends StatelessWidget {
  const LevelInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = CountryScope.of(context).strings;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(LucideIcons.arrow_left, size: 24, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(LucideIcons.award, size: 22, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              s.get('levelInfo'),
              style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: LevelService.instance.totalPointsNotifier,
        builder: (context, totalPoints, _) {
          final currentLevel = LevelService.instance.getLevel(totalPoints);
          final pointsForCurrent = LevelService.pointsRequiredForLevel(currentLevel);
          final pointsForNext = currentLevel < 30
              ? LevelService.pointsRequiredForLevel(currentLevel + 1)
              : LevelService.pointsRequiredForLevel(30);
          final segmentSize = pointsForNext - pointsForCurrent;
          final progressInSegment = segmentSize > 0
              ? (totalPoints - pointsForCurrent).clamp(0, segmentSize)
              : 0;
          final pointsNeededForNext = currentLevel < 30 ? pointsForNext - totalPoints : 0;

          return ListView(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 32 + MediaQuery.of(context).padding.bottom + 0),
            children: [
              Text(
                s.get('levelInfoSubtitle'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              // 현재 레벨
              Text(
                s.get('currentLevel'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outline.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LevelBadgeLarge(level: currentLevel),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Level $currentLevel',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${s.get('totalPointsLabel')} ${_formatPoints(totalPoints)}',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (currentLevel < 30) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: segmentSize > 0
                                    ? progressInSegment / segmentSize
                                    : 0.0,
                                minHeight: 8,
                                backgroundColor: cs.outline.withOpacity(0.2),
                                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '$progressInSegment / $segmentSize',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.get('nextLevelNeeded').replaceFirst('N', '${_formatPoints(pointsNeededForNext)}'),
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            'Level ${currentLevel + 1}',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Level 30 · ${s.get('levelAchieved')}',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _levelColor(30),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                s.get('entireLevelSystem'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.get('levelSystemDescription'),
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              // 테이블 헤더
              Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      s.get('level'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 44,
                    child: Text(
                      s.get('tableIcon'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      s.get('attainmentPoint'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      s.get('achievementStatus'),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: cs.outline.withOpacity(0.3)),
              // 레벨 1~30 행
              ...List.generate(30, (i) {
                final level = i + 1;
                final pointsRequired = LevelService.pointsRequiredForLevel(level);
                final prevRequired = level > 1 ? LevelService.pointsRequiredForLevel(level - 1) : 0;
                final diff = pointsRequired - prevRequired;
                final isAchieved = totalPoints >= pointsRequired;
                final isCurrent = currentLevel == level;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text(
                              '$level',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _LevelBadgeSmall(level: level),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              level == 1
                                  ? '0 ${s.get('points')}'
                                  : '${_formatPoints(pointsRequired)} ${s.get('points')}${diff > 0 ? ' (+${_formatPoints(diff)})' : ''}',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: isCurrent
                                ? Text(
                                    s.get('currentLevelLabel'),
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary,
                                    ),
                                  )
                                : isAchieved
                                    ? Icon(Icons.check_circle, size: 20, color: cs.primary)
                                    : Text(
                                        s.get('levelNotAchieved'),
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: cs.outline.withOpacity(0.15)),
                  ],
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _LevelBadgeLarge extends StatelessWidget {
  const _LevelBadgeLarge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(level);
    final isMax = level >= 30;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(isMax ? 0.25 : 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: isMax ? 2 : 1.5),
      ),
      child: Center(
        child: Text(
          '$level',
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _LevelBadgeSmall extends StatelessWidget {
  const _LevelBadgeSmall({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(level);
    final isMax = level >= 30;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withOpacity(isMax ? 0.25 : 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: isMax ? 1.5 : 1),
      ),
      child: Center(
        child: Text(
          '$level',
          style: GoogleFonts.notoSansKr(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}
