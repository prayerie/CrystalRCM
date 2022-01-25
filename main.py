import os
import io
from tkinter import ACTIVE, DISABLED, END, NORMAL, Frame, Label, Listbox, Text, Tk, ttk
from tkinter import filedialog as fd
from tkinter import messagebox
from tkinter import Toplevel
from tkinter import Image as TKImage, PhotoImage
import argparse
import fusee_launcher
import threading
import time
import queue

from payload_signature import BRICCMII, FUSEE, HEKATE_LOCKPICK, REI, SWITCHBREW_STRING

out = ""


global arguments
global img_success
global last_state
global threaded_task

status_icon = None
tk_combo_box = None
app = None
window = None

tk_push_button = None
tk_debug_output = None

last_was_push = False
last_was_non_rcm = False

payload_type = -1

threaded_task = None
stop_event = threading.Event()

RCM_VID = 0x0955
RCM_PID = 0x7321

NORMAL_VID = 0x057E
NORMAL_PID = 0x2000


class ThreadedTask(threading.Thread):
    """Poll USB for a device on a different thread.

    Args:
        threading ([type]): the thread itself
    """
    global last_state
    last_state = False

    def __init__(self, queue):
        super().__init__()
        self.queue = queue

    def run(self):
        global status_icon, tk_debug_output, tk_push_button, last_was_push, last_was_non_rcm, last_state
        last_state = False
        non_rcm_prev = False

        while True:
            # quit gracefully on close
            if stop_event.is_set():
                break

            # if not tk_debug_output or not tk_push_button:
            #     continue

            norm_switch = fusee_launcher.cr_find_device(
                vid=NORMAL_VID, pid=NORMAL_PID) is not None
            rcm_switch = fusee_launcher.cr_find_device(
                vid=RCM_VID, pid=RCM_PID) is not None

            if norm_switch:
                if not last_was_non_rcm:
                    addOutputText(tk_debug_output,
                                  "Non-RCM Switch connected.\n")
                    if not non_rcm_prev and app is not None:
                        # we're on a different thread so we need to use an event rather than
                        # directly showing a dialog box, otherwise we get a SIGTRAP
                        window.event_generate("<<nrcm>>", when="tail")
                    last_was_non_rcm = True
                    non_rcm_prev = True
                    status_icon = get_image('assets/s_waiting.png')
                    panel.configure(image=status_icon)
            elif rcm_switch:
                try:
                    fusee_launcher.RCMHax()._find_device()

                    if last_was_push:
                        continue

                    if last_state == False:
                        addOutputText(tk_debug_output,
                                      "RCM device connected!\n")
                        last_state = True
                        last_was_non_rcm = False
                        non_rcm_prev = False

                    tk_push_button.configure(default="active")
                    tk_push_button.configure(state=ACTIVE)
                    status_icon = get_image('assets/s_ready.png')
                    if last_state == False or 1:
                        panel.configure(image=status_icon)
                    last_state = True
                except IOError:
                    if last_state == True:
                        addOutputText(tk_debug_output,
                                      "RCM device disconnected!\n")
                        last_state = False
                    last_was_non_rcm = False
                    tk_push_button.configure(default="disabled")
                    tk_push_button.configure(state=DISABLED)
                    status_icon = get_image('assets/s_waiting.png')
                    panel.configure(image=status_icon)
                    self.last_state = False
            else:
                last_was_push = False
                if last_state and not last_was_push:
                    addOutputText(tk_debug_output,
                                  "RCM device disconnected!\n")
                    last_state = False
                if last_was_non_rcm:
                    addOutputText(tk_debug_output,
                                  "Non-RCM Switch disconnected?\n")
                    last_was_non_rcm = False

            time.sleep(0.3)


class Combobox(ttk.Combobox):
    def _tk(self, cls, parent):
        obj = cls(parent)
        obj.destroy()
        if cls is Toplevel:
            obj._w = self.tk.call('ttk::combobox::PopdownWindow', self)
        else:
            obj._w = '{}.{}'.format(parent._w, 'f.l')
        return obj

    def __init__(self, parent, **kwargs):
        super().__init__(parent, **kwargs)
        self.popdown = self._tk(Toplevel, parent)
        self.listbox = self._tk(Listbox, self.popdown)

        self.bind("<KeyPress>", self.on_keypress, '+')
        self.listbox.bind("<Up>", self.on_keypress)

    def on_keypress(self, event):
        if event.widget == self:
            state = self.popdown.state()

            if state == 'withdrawn' \
                    and event.keysym not in ['BackSpace', 'Up']:
                self.event_generate('<Button-1>')
                self.after(0, self.focus_set)

            if event.keysym == 'Down':
                self.after(0, self.listbox.focus_set)

        else:  # self.listbox
            curselection = self.listbox.curselection()

            if event.keysym == 'Up' and curselection[0] == 0:
                self.popdown.withdraw()


__location__ = os.path.realpath(
    os.path.join(os.getcwd(), os.path.dirname(__file__)))


def get_image(path: str):
    img = PhotoImage(file=local(path))
    return img


def addOutputText(textWidget: Text, content: str):
    textWidget.configure(state=NORMAL)
    textWidget.insert(END, content)
    textWidget.see(END)
    textWidget.configure(state=DISABLED)


def local(name: str):
    return os.path.join(__location__, name)


def show_non_rcm_warning(evt):
    app.warn(title="Not in recovery mode!",
             message="You have just connected a Nintendo Switch that isn't in recovery mode.\n\nPlease boot to RCM.")


def push():
    global payload_type, img_success, last_was_push

    payload_path = tk_combo_box.get()

    if os.path.isfile(payload_path):
        with open(payload_path, "rb") as f:
            target_payload = f.read()
    else:
        addOutputText(tk_debug_output,
                      f"Invalid payload path specified!\n❌{payload_path}\n")
        messagebox.showerror(title="Invalid path.",
                             message="That file doesn't exist.")
        app.refresh()
        return

    existing_list = []
    if os.path.isfile('recent_dirs.txt'):
        with open('recent_dirs.txt', 'r') as f:
            existing_list = f.readlines()

    with open('recent_dirs.txt', 'w') as f:
        existing_list.append(payload_path)

        for ele in unique(existing_list):
            if ele == '\n':
                continue
            ele = ele.strip('\n')
            f.write(ele + "\n")

    payload_type = get_payload_type(target_payload)

    last_was_push = True
    f = io.StringIO()
    result = fusee_launcher.try_push(target_payload, arguments)

    # show the appropriate success image based on the payload they push
    if result == 0:
        match payload_type:
            case 0:
                img_name = 's_ams'
            case 1:
                img_name = 's_hkt'
            case 2:
                img_name = 's_reinx'
            case 3:
                img_name = 's_bricc'
            case 4:
                img_name = 's_lockpick'
            case 5:
                img_name = 's_generic'

        img_success = get_image(f'assets/{img_name}.png')
        panel.configure(image=img_success)
        panel.update()
        addOutputText(tk_debug_output, "Launch success!\n")

        messagebox.showinfo(
            title="Success!", message="Pushed payload successfully!")

    elif result == 1:
        length = 0x30298
        size_over = len(target_payload) - length
        addOutputText(
            tk_debug_output, f"ERROR: Payload is too large to be submitted via RCM. ({size_over} bytes larger than max).")

        messagebox.showwarning(title="Payload too large.",
                               message=f"Couldn't send your payload.\nIt is {size_over} bytes too large.")
    elif result == 2:
        addOutputText(
            tk_debug_output, "Could not find the intermezzo interposer. Did you build it?")
        messagebox.showwarning(
            title="Missing file.", message=f"intermezzo.bin is missing from the app's assets folder.")
    elif result == 3:
        addOutputText(tk_debug_output, "Invalid payload path specified!")
    elif result == 4:
        messagebox.showwarning(
            title="Invalid device.", message=f"Invalid device.\nAre you trying to push to a Switch outside of recovery mode?")
    app.refresh()


def set_payload():
    """Open a file chooser dialogue, and then scroll the ComboBox to the end.
    """
    filename = fd.askopenfilename()
    tk_combo_box.set(filename)
    tk_combo_box.xview(END)

def unique(list):
    """Make a list unique whilst preserving its order.

    Args:
        list ([type]): input list

    Returns:
        list: the processed list
    """
    seen = set()
    return [x for x in list if not (x in seen or seen.add(x))]
class CrystalRCM(Frame):
    def __init__(self, parent, *args, **kwargs):
        Frame.__init__(self, parent, *args, **kwargs)
        self.parent = parent

        parent.protocol("WM_DELETE_WINDOW", on_close)
        global status_icon, panel, tk_push_button, tk_combo_box
        status_icon = get_image('assets/s_waiting.png')
        panel = Label(parent, image=status_icon)
        panel.image = status_icon
        panel.grid(row=0, column=0, sticky='n', pady=16, rowspan=2, padx=8)

        tk_push_button = ttk.Button(parent, text='Push!', command=push)
        tk_push_button.grid(row=0, column=2, sticky='W', pady=8, padx=4)

        tk_push_button.configure(default="disabled")
        tk_push_button.configure(state=DISABLED)

        choosedir = ttk.Button(parent, text='Payload...', command=set_payload)
        choosedir.grid(row=0, column=3, sticky='W', pady=8, padx=4)

        imgc = TKImage("photo", file=local('assets/icon.png'))

        values = []

        if os.path.isfile('recent_dirs.txt'):
            with open('recent_dirs.txt', 'r') as f:
                values = [line.rstrip('\n') for line in f]

        values = unique(values)[:5]

        tk_combo_box = Combobox(parent, value=values)
        tk_combo_box.grid(row=0, column=1, sticky='E', pady=8, padx=4)

        if len(values) > 0:
            tk_combo_box.set(values[-1])
            tk_combo_box.xview(END)

        parent.tk.call('wm', 'iconphoto', parent._w, imgc)

        global tk_debug_output
        tk_debug_output = Text(parent, height=5, width=60, relief='sunken')
        tk_debug_output.grid(row=1, column=1, columnspan=3, sticky='n')

        parent.geometry("540x140")
        parent.title('CrystalRCM')

    def refresh(self):
        global last_was_push
        global last_was_non_rcm
        global last_state

        last_was_push = False
        #last_was_non_rcm = False
        last_state = False

    def warn(self, title, message):
        messagebox.showwarning(title=title, message=message)


def get_payload_type(payload):
    """0: Fusee
    1: Hekate
    2: ReiNX
    3: briccMii
    4: LockPickRCM
    -1: other
    """
    header = payload[:5]
    if header == FUSEE:
        return 0
    if header == REI:
        return 2
    if header == BRICCMII:
        return 3
    if header == HEKATE_LOCKPICK:
        if SWITCHBREW_STRING in payload:
            return 1
        else:
            return 4
    return -1


def on_close():
    stop_event.set()
    threaded_task.join()
    window.destroy()


def main():
    global parser, arguments, payload_type, window, app, threaded_task
    queues = queue.Queue()
    threaded_task = ThreadedTask(queues)
    

    window = Tk()
    window.resizable(False, False)
    window.bind("<<nrcm>>", show_non_rcm_warning)

    parser = argparse.ArgumentParser(
        description='launcher for the fusee gelee exploit (by @ktemkin)')
    arguments = parser.parse_args()

    app = CrystalRCM(window)
    app.grid(row=0, column=0)
    window.mainloop()
    threaded_task.start()


if __name__ == '__main__':
    main()
