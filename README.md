# Reminiscia
## About
Reminiscia is a mobile offline image searching app based on CLIP

## Desktop (PyTorch)

```bash
$ conda install --yes -c pytorch pytorch=1.7.1 torchvision cudatoolkit=11.0
$ pip install ftfy regex tqdm
$ pip install git+https://github.com/openai/CLIP.git
```

### Steps to run CLIP on desktop:
- Add images to album folder (convert HEIC into JPG)
- Compute image features with `$ python build_index.py`, the features will be stored to `image_features.pt`
- Query the images with `$ python query_index.py {query}`
