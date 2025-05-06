import typer
from typing import Optional
from typing_extensions import Annotated

from modelscope.hub.constants import DEFAULT_MAX_WORKERS 
from modelscope.hub.snapshot_download import DEFAULT_MODEL_REVISION

import numpy as np

import logging
from rich.logging import RichHandler

log = logging.getLogger(__name__)

def init_logging():
    FORMAT = "%(message)s"
    
    logging.basicConfig(
        level="INFO", format=FORMAT, datefmt="[%X]", handlers=[RichHandler()]
    )

    global log
    log = logging.getLogger(__name__)


app = typer.Typer()

@app.command()
def huggingface(
    model_id: Annotated[str, typer.Option()],
    job_index: Annotated[int, typer.Option(envvar="JOB_COMPLETION_INDEX")],
    job_total: Annotated[int, typer.Option(envvar="JOB_COMPLETION_TOTAL")],
    revision: Optional[str] = None,
    cache_dir: Optional[str] = None,
    token: Optional[str] = None,
    local_dir: Optional[str] = None,
    dry_run: Optional[bool] = False,
):
    from huggingface_hub import hf_hub_download, snapshot_download 
    from huggingface_hub import HfApi
    log.info("use huggingface to download")
    _api = HfApi(library_name="huggingface-cli")
    repo_info = _api.repo_info(
        repo_id=model_id,
        repo_type="model",
        token=token,
        revision=revision,
    )

    modelfiles= [v.rfilename for v in repo_info.siblings]
    downloadfiles = filter_download_files(modelfiles, job_index, job_total)
    
    log.info(f"this job will download {len(downloadfiles)} files:")
    for f in downloadfiles:
        log.info(f"==> {f}")
    
    if dry_run:
        log.info("running in dryrun mode, exit")
        return

    if len(downloadfiles) == 1:
        hf_hub_download(
            repo_id=model_id,
            repo_type="model",
            revision=revision,
            filename=downloadfiles[0],
            cache_dir=cache_dir,
            token=token,
            local_dir=local_dir,
            library_name="huggingface-cli",
        )
    elif len(downloadfiles) > 1:
        snapshot_download(
            repo_id=model_id,
            repo_type="model",
            revision=revision,
            allow_patterns=downloadfiles,
            cache_dir=cache_dir,
            token=token,
            local_dir=local_dir,
            library_name="huggingface-cli",
            max_workers=DEFAULT_MAX_WORKERS,
        )

    log.info("download finished")


@app.command()
def modelscope(
    model_id: Annotated[str, typer.Option()],
    job_index: Annotated[int, typer.Option(envvar="JOB_COMPLETION_INDEX")],
    job_total: Annotated[int, typer.Option(envvar="JOB_COMPLETION_TOTAL")],
    revision: Optional[str] = DEFAULT_MODEL_REVISION,
    cache_dir: Optional[str] = None,
    token: Optional[str] = None,
    local_dir: Optional[str] = None,
    dry_run: Optional[bool] = False,
):
    from modelscope.hub.api import HubApi
    from modelscope.hub.file_download import model_file_download
    from modelscope.hub.snapshot_download import snapshot_download
    log.info("use modelscope to download")
    _api = HubApi()
    
    cookies = None
    if token:
        cookies = _api.get_cookies(access_token=token)

    modelfiles_and_dir = _api.get_model_files(model_id=model_id)
    modelfiles = [f["Path"] for f in modelfiles_and_dir if f['Type'] != 'tree']
    downloadfiles = filter_download_files(modelfiles, job_index, job_total)
    
    log.info(f"this job will download {len(downloadfiles)} files:")
    for f in downloadfiles:
        log.info(f"==> {f}")

    if dry_run:
        log.info("running in dryrun mode, exit")
        return

    if len(downloadfiles) == 1:
        model_file_download(
            model_id=model_id, 
            file_path=downloadfiles[0], 
            revision=revision,
            cache_dir=cache_dir,
            local_dir=local_dir,
            cookies=cookies,
        )
    elif len(downloadfiles) > 1:
        snapshot_download(
            model_id=model_id,
            revision=revision,
            cache_dir=cache_dir,
            local_dir=local_dir,
            allow_file_pattern=downloadfiles,
            max_workers=DEFAULT_MAX_WORKERS,
            cookies=cookies,
        )
    
    log.info("download finished")

def filter_download_files(
    files: list,
    job_index: int,
    job_total: int,
) -> list:
    ret = []
    if job_index == 0:
        ret = [f for f in files if not f.endswith(".safetensors")]
    
    tensor_files = [f for f in files if f.endswith(".safetensors")]
    tensor_files = sorted(tensor_files, key=lambda x: x)
    tensor_files_splited = np.array_split(tensor_files, job_total)
    if job_index < len(tensor_files_splited):
        ret.extend(tensor_files_splited[job_index])
    
    return ret

if __name__ == "__main__":
    init_logging()
    app()
