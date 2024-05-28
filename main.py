import sys
import subprocess
import json
from datetime import datetime
import pytz

CMD = '''
ffmpeg -y -hide_banner \\
    -i {input} \\
    \\
    -c:v libx264 -crf 22 -preset veryslow \\
    -vf scale=1920:1080{extra_vf} \\
    \\
    -c:a copy \\
    \\
    -map_metadata 0 \\
    -metadata creation_time={ctime} \\
    -movflags +faststart \\
    \\
    {output}
'''

ROTATE_LEFT = False

def get_ffprobe_info(filename):
    command = ['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_format', '-show_streams', filename]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0
    return json.loads(result.stdout)

def get_tag(d, tag):
    return d['tags'][tag]

def handle_video(filename):
    filename = "DSCN2040.MP4"
    info = get_ffprobe_info(filename)

    creation_time = get_tag(info['format'], 'creation_time')
    print(f'Original creation time: {creation_time}')

    for i, s in enumerate(info['streams']):
        assert creation_time == get_tag(s, 'creation_time')
        print(f'  Same in stream {i}: {s["codec_type"]}')

    bad_time = datetime.strptime(creation_time, "%Y-%m-%dT%H:%M:%S.%fZ")
    correct_time = bad_time.astimezone(pytz.timezone('Asia/Shanghai'))
    print(f'Parsed into: {correct_time}')

    formatted_time = correct_time.astimezone(pytz.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    print()
    print(f'Original: {creation_time}')
    print(f'Updated:  {formatted_time}')

    print(CMD.format(
        input=filename,
        ctime=formatted_time,
        output='output.mp4',
        extra_vf=',transpose=2' if ROTATE_LEFT else '',
    ))

if __name__ == '__main__':
    if len(sys.argv) == 1:
        print('Usage: main.py [-left] VIDEO...')
        sys.exit(1)

    for filename in sys.argv[1:]:
        if filename == '-left':
            ROTATE_LEFT = True
            break
    
    for filename in sys.argv[1:]:
        if filename == '-left':
            continue
        handle_video(filename)
