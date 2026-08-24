'use strict';

// Captured from the UHDNow API on 2026-08-24. Playback URLs preserve the
// observed capability-token query shape while redacting the secret value.
// Episode and asset metadata retain their observed values.
module.exports = Object.freeze({
  seriesID: '01M0DC5D0QZYMW6T8WRPEWVZ7T',
  seasonID: '01M0DC5E6FTRAV3N6QVTVN5TKK',
  episodes: Object.freeze([
    Object.freeze({
      id: '01M0DC5EPWVZXA95RF8FR4RTKJ',
      number: 2,
      title: '第 2 集',
      durationSeconds: 2473,
      asset: Object.freeze({
        id: '01M0DC5ESJ2ZR3AC9C3V80Y4SD',
        name: '师兄太稳健 - S01E02 - 第 2 集 - 1080p - WEB-DL.mkv',
        resolution: '1080p',
        encoding: 'h264',
        playbackURL:
          'https://v1-vod1.uhdnow.com/play/video/01M0DC5ESJ2ZR3AC9C3V80Y4SD?token=<redacted>',
      }),
    }),
    Object.freeze({
      id: '01M0DC5F212PHRAPV6B4JQYT0Y',
      number: 3,
      title: '第 3 集',
      durationSeconds: 2963,
      asset: Object.freeze({
        id: '01M0DC5F4BRJHQ5QWHXHACMFV0',
        name: '师兄太稳健 - S01E03 - 第 3 集 - 1080p - WEB-DL.mkv',
        resolution: '1080p',
        encoding: 'h264',
        playbackURL:
          'https://v1-vod1.uhdnow.com/play/video/01M0DC5F4BRJHQ5QWHXHACMFV0?token=<redacted>',
      }),
    }),
  ]),
});
