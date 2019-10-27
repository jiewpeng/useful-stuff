# Transcode Video to DNXHD

To transcode a 720p file to DNXHD:

```bash
ffmpeg -i $input -c:v dnxhd -pix_fmt yuv422p -b:v 60M $output.mov
```

If it's 10 bit:

```bash
ffmpeg -i $input -c:v dnxhd -pix_fmt yuv422p10 -b:v 90M $output.mov
```

To transcode a 1080p file to DNXHD:

```bash
ffmpeg -i $input -c:v dnxhd -pix_fmt yuv422 -b:v 36M $output.mov
```

etc. If there are errors, just look at the output and see the available combinations of frame size, bitrate and pixel format. 
