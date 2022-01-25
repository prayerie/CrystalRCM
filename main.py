import os, io
from tkinter import ACTIVE, DISABLED, END, NORMAL, Frame, Image, Label, Listbox, Text, Tk, ttk
from tkinter import filedialog as fd
from tkinter import messagebox
from tkinter import Toplevel
from tkinter import Image as TKImage, PhotoImage
import argparse
import flaunch
import threading
import time
import queue

from payload_signature import BRICCMII, FUSEE, HEKATE_LOCKPICK, REI, SWITCHBREW_STRING

out = ""

btn = None
st = None
global arguments
img = None
cb = None
app = None
window = None
global img_success
global last_state
global t
just_launched = False
just_warned = False

payload_type = -1


stop_event = threading.Event()

RCM_VID = 0x0955
RCM_PID = 0x7321

NORMAL_VID = 0x057E
NORMAL_PID = 0x2000


class ThreadedTask(threading.Thread):
    global last_state
    last_state = False
    
    def __init__(self, queue):
        super().__init__()
        self.queue = queue

    def run(self):
        global img, st, btn, just_launched, just_warned, last_state
        last_state = False
        non_rcm_prev = False

        while True:
            if stop_event.is_set():
                break

            if not st or not btn:
                continue

            norm_switch = flaunch.cr_find_device(vid=NORMAL_VID, pid=NORMAL_PID) is not None
            rcm_switch = flaunch.cr_find_device(vid=RCM_VID, pid=RCM_PID) is not None

            if norm_switch:
                if not just_warned:
                    addOutputText(st, "Non-RCM Switch connected.\n")
                    if not non_rcm_prev and app is not None:
                        window.event_generate("<<nrcm>>", when="tail", state=123)
                    just_warned = True
                    non_rcm_prev = True
            elif rcm_switch:
                try:
                    flaunch.RCMHax()._find_device()

                    if just_launched:
                        continue

                    if last_state == False:
                        addOutputText(st, "RCM device connected!\n")
                        last_state = True
                        just_warned = False
                        non_rcm_prev = False

                    btn.configure(default="active")
                    btn.configure(state=ACTIVE)
                    img = get_image('assets/s_ready.png')
                    if last_state == False or 1:
                        panel.configure(image=img)
                    last_state = True
                except IOError:
                    if last_state == True:
                        addOutputText(st, "RCM device disconnected!\n")
                        last_state = False 
                    just_warned = False
                    btn.configure(default="disabled")
                    btn.configure(state=DISABLED)
                    img = get_image('assets/s_waiting.png')
                    panel.configure(image=img)
                    self.last_state = False
            else:
                just_launched = False
                if last_state:
                    addOutputText(st, "RCM device disconnected!\n")
                    last_state = False
                if just_warned:
                    addOutputText(st, "Non-RCM Switch disconnected?\n")
                    just_warned = False

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

def eventhandler(evt):  
    app.warn(title="Not in recovery mode!", 
    message="You have just connected a Nintendo Switch that isn't in recovery mode.\n\nPlease boot to RCM.")

def push():
    global payload_type, img_success, just_launched

    payload_path = cb.get()

    if os.path.isfile(payload_path):
        with open(payload_path, "rb") as f:
            target_payload = f.read()
    else:
        addOutputText(st, f"Invalid payload path specified!\n❌{payload_path}\n")
        messagebox.showerror(title="Invalid path.", message="That file doesn't exist.")
        app.refresh()
        return

    existing_list = []
    if os.path.isfile('recent_dirs.txt'):
         with open('recent_dirs.txt', 'r') as f:
            existing_list = f.readlines()
        
            
    with open('recent_dirs.txt', 'w') as f:
        if payload_path not in existing_list:
            existing_list.append(payload_path)
        for ele in existing_list:
            if ele == '\n':
                del(ele)
                continue
            ele = ele.strip('\n')
            f.write(ele + "\n")
    
        
    payload_type = get_payload_type(target_payload)
    

    just_launched = True
    f = io.StringIO()
    result = flaunch.trypush(target_payload, arguments)
    
    if result == 0:
        if payload_type == 0:
            img_name = 's_ams'
        if payload_type == 1:
            img_name = 's_hkt'
        if payload_type == 2:
            img_name = 's_reinx'
        if payload_type == 3:
            img_name = 's_bricc'
        if payload_type == 4:
            img_name = 's_lockpick'
        if payload_type == 5:
            img_name = 's_generic'
        img_success = get_image(f'assets/{img_name}.png')
        panel.configure(image=img_success)
        panel.update()
        addOutputText(st, "Launch success!\n")
        
        messagebox.showinfo(title="Success!", message="Pushed payload successfully!")
    elif result == 1:
        length  = 0x30298
        size_over = len(target_payload) - length
        addOutputText(st, f"ERROR: Payload is too large to be submitted via RCM. ({size_over} bytes larger than max).")
        
        messagebox.showwarning(title="Payload too large.", message=f"Couldn't send your payload.\nIt is {size_over} bytes too large.")
    elif result == 2:
        addOutputText(st, "Could not find the intermezzo interposer. Did you build it?")
        messagebox.showwarning(title="Missing file.", message=f"intermezzo.bin is missing from the app's assets folder.")
    elif result == 3:
        addOutputText(st, "Invalid payload path specified!")
    elif result == 4:
        messagebox.showwarning(title="Invalid device.", message=f"Invalid device.\nAre you trying to push to a Switch outside of recovery mode?")
    app.refresh()

def set_payload():
    filename = fd.askopenfilename()
    cb.set(filename)
    cb.xview(END)

class CrystalRCM(Frame):
    def __init__(self, parent, *args, **kwargs):
        Frame.__init__(self, parent, *args, **kwargs)
        self.parent = parent

        parent.protocol("WM_DELETE_WINDOW", on_close)
        global img, panel, btn, cb
        img = get_image('assets/s_waiting.png')
        #The Label widget is a standard Tkinter widget used to display a text or image on the screen.
        panel = Label(parent, image = img)
        panel.image = img
        #The Pack geometry manager packs widgets in rows or columns.
        panel.grid(row=0, column=0, sticky='n', pady=16, rowspan=2, padx=8)

        btn=ttk.Button(parent, text='Push!', command=push)
        btn.grid(row=0, column=2, sticky='W', pady=8, padx=4)

        btn.configure(default="disabled")
        btn.configure(state=DISABLED)
        
        choosedir=ttk.Button(parent, text='Payload...', command=set_payload)
        choosedir.grid(row=0, column=3, sticky='W', pady=8, padx=4)
        #window.iconbitmap(os.path.join(__location__, 'icon.ico'))
        imgc = TKImage("photo", file=local('assets/icon.png'))

        

        values = []
        
        if os.path.isfile('recent_dirs.txt'):
            with open('recent_dirs.txt', 'r') as f:
                values = [line.rstrip('\n') for line in f]

        values = list(reversed(values))[:5]
        values = list(set(values))
        
        cb = Combobox(parent, value=values)
        cb.grid(row=0, column=1, sticky='E', pady=8, padx=4)
        
        if len(values) > 0:
            cb.set(values[0])
            cb.xview(END)

        parent.tk.call('wm','iconphoto', parent._w, imgc)

        global st
        st = Text(parent, height=5, width=60, relief='sunken')
        st.grid(row=1,column=1, columnspan=3, sticky='n')
        #st.config(state=DISABLED)

        
        parent.geometry("540x140")
        parent.title('CrystalRCM')

    def refresh(self):
        global just_launched
        global just_warned
        global last_state

        
        just_launched = False
        just_warned = False
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
    t.join()
    window.destroy()

def main():
    global parser, arguments, payload_type, window, app, t
    queues = queue.Queue()
    t = ThreadedTask(queues)
    t.start()
    window = Tk()
    window.resizable(False, False)
    window.bind("<<nrcm>>", eventhandler)
    
    parser = argparse.ArgumentParser(description='launcher for the fusee gelee exploit (by @ktemkin)')
    arguments = parser.parse_args()

    
    

    

    
    
    app = CrystalRCM(window)
    app.grid(row=0, column=0)
    window.mainloop()

if __name__ == '__main__':
    main()