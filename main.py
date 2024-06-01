import os
import subprocess
import json
from datetime import datetime
import pytz
import argparse

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

def get_ffprobe_info(filename):
    command = ['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_format', '-show_streams', filename]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0
    return json.loads(result.stdout)

def get_tag(d, tag):
    return d['tags'][tag]

def handle_video(filename, output, rotate_left, dry_run):
    print("=========================================")
    print(f"= Input:  {filename}")
    print(f"= Output: {output}")
    print("=========================================")
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

    cmd = CMD.format(
        input=filename,
        ctime=formatted_time,
        output=output,
        extra_vf=',transpose=2' if rotate_left else '',
    )
    if dry_run:
        print(cmd)
    else:
        os.system(cmd)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Nikon P950 video compression tool')
    parser.add_argument('-l', '--left', action='store_true',
                        help='Rotate all videos 90 degrees to the left')
    parser.add_argument('-n', '--dryrun', action='store_true',
                        help='Print the commands instead of executing them')
    parser.add_argument('videos', nargs='+', help='Videos to compress')

    args = parser.parse_args()

    for filename in args.videos:
        # split into directory, basename, extension
        directory, basename = os.path.split(filename)
        basename, extension = os.path.splitext(basename)
        print(directory, basename, extension)

        output = os.path.join(directory, 'compressed', f'{basename}_c{extension}')
        if not args.dryrun:
            os.makedirs(os.path.dirname(output), exist_ok=True)

        handle_video(filename, output, args.left, args.dryrun)
