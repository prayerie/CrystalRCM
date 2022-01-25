from tkinter import Listbox, Toplevel, ttk


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
