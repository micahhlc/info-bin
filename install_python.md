**The Direct Answer**
To install the absolute latest stable version of Python available in `pyenv`, run this command:

```bash
pyenv install $(pyenv install --list | grep -v - | grep -v b | tail -1)
```
*(This command automatically finds the highest number without alpha/beta tags and installs it.)*

**Or simply pick the highest number manually:**
1.  List all available versions:
    ```bash
    pyenv install --list | grep " 3\."
    ```
    *(Scroll to the bottom to see the latest, e.g., `3.12.1` or `3.13.0`)*
2.  Install it:
    ```bash
    pyenv install 3.12.1
    ```
3.  Set it as global:
    ```bash
    pyenv global 3.12.1
    ```

**The Explanation**
*   **`pyenv install --list`**: Shows every version of Python ever released (including Anaconda, PyPy, etc.).
*   **`grep -v -`**: Filters out prerelease versions (like `3.13.0-dev`).
*   **`grep -v b`**: Filters out beta versions (like `3.13.0b1`).
*   **`tail -1`**: Grabs the very last line, which is the newest stable release.

**The Best Practice**
**Stick to the latest "Patch" release of the previous "Minor" version (e.g., 3.11.x instead of 3.12.0) for production stability.**
New "Minor" versions (like 3.12.0) often break third-party libraries (pandas, numpy, etc.) for a few months until they catch up.

**Safe Bet for Today:** `3.11.7` (or whatever the latest 3.11 patch is). It's fast, stable, and widely supported.