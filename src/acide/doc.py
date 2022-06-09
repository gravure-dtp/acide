# -*- coding: utf-8 -*-
# doc.py
#
# Copyright 2022 Gilles Coissac
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
"""Acide doc module.

NOTES ON PYMUDF COORDINATES:
  Methods require coordinates (points, rectangles) to put content
in desired places. Please be aware that since MuPdf v1.17.0 these coordinates
must always be provided relative to the unrotated page.
  The reverse is also true: except Page.rect, resp. Page.bound()
(both reflect when the page is rotated), all coordinates returned by methods
and attributes pertain to the unrotated page.
  So the returned value of e.g. Page.get_image_bbox() will not change if you
do a Page.set_rotation(). The same is true for coordinates returned
by Page.get_text(), annotation rectangles, and so on.
  If you want to find out, where an object is located in rotated coordinates,
multiply the coordinates with Page.rotation_matrix. There also is its inverse,
Page.derotation_matrix, which you can use when interfacing with other readers,
which may behave differently in this respect.

MEDIABOX: A PDF array of 4 floats specifying a physical page size.
  This rectangle should contain all other PDF – optional – page rectangles,
which may be specified in addition: CropBox, TrimBox, ArtBox and BleedBox.
Please consult Adobe PDF References for details.
  The MediaBox is the only rectangle, for which there is no difference between
MuPDF and PDF coordinate systems: Page.mediabox will always show the same
coordinates as the /MediaBox key in a page’s object definition. For all
other rectangles, MuPDF transforms coordinates such that the top-left corner
is the point of reference. This can sometimes be confusing – you may for example
encounter a situation like this one:
  * The page definition contains the following identical values:
    /MediaBox [ 36 45 607.5 765 ], /CropBox [ 36 45 607.5 765 ].
  * PyMuPDF accordingly shows page.mediabox = Rect(36.0, 45.0, 607.5, 765.0).
  * BUT: page.cropbox = Rect(36.0, 0.0, 607.5, 720.0), because the two y-coordinates
    have been transformed (45 subtracted from both of them).
"""
from pathlib import Path
from typing import List

from gi.repository import Gdk, GLib, GObject, Graphene

import fitz

#TODO: Duplex Class

class Document():
    """Acide Document.

    NOTE ON PYMUPDF USAGE:
    Never access a Page object, after you have closed (or deleted
    or set to None) the owning Document. Or, less obvious: never access
    a page or any of its children (links or annotations) after you have
    executed one of the document methods select(), delete_page(),
    insert_page() … and more.

    The required logic has therefore been built into PyMuPDF
    itself in the following way:
       * If a page “loses” its owning document or is being deleted itself,
         all of its currently existing annotations and links will be made
         unusable in Python, and their C-level counterparts will be deleted
         and deallocated.
       * If a document is closed (or deleted or set to None) or if its
         structure has changed, then similarly all currently existing pages
         and their children will be made unusable, and corresponding C-level
         deletions will take place. “Structure changes” include methods like
         select(), delePage(), insert_page(), insert_pdf() and so on:
         all of these will result in a cascade of object deletions.

    The programmer will normally not realize any of this. If he, however,
    tries to access invalidated objects, exceptions will be raised.
    see: https://pymupdf.readthedocs.io/en/latest/app3.html

    Invalidated objects cannot be directly deleted as with Python statements
    like del page or page = None, etc. Instead, their __del__ method must
    be invoked.

    All pages, links and annotations have the property parent, which points
    to the owning object. This is the property that can be checked
    on the application level: if obj.parent == None then the object’s parent
    is gone, and any reference to its properties or methods will raise
    a RuntimeError informing about this “orphaned” state.

    Objects outside the above relationship are not included in this mechanism.
    If you e.g. created a table of contents by toc = doc.get_toc(), and later
    close or change the document, then this cannot and does not change variable
    toc in any way. It is your responsibility to refresh such variables as required.
    """
    def __init__(self, file: Path = None) -> Document:
        self._pdf: fitz.Document = None
        self.pages: List[fitz.Page] = []


class Page(GObject.GObject):
    """Page Document.
    """

    __gtype_name__ = "Page"
    __gproperties__ = {
        "mediabox": (
			object,
            "mediabox",
    		"a Graphene Rect representing the Page.mediabox",
            GObject.ParamFlags.READABLE,
        ),
        "cropbox": (
			object,
    		"cropbox",
    		("a Graphene Rect representing the Page.cropbox."
    		 "Specified in unrotated coordinates, not empty, nor infinite "
    		 "and be completely contained in the Page.mediabox."),
            GObject.ParamFlags.READABLE,
        ),
        "artbox": (
			object,
    		"artbox",
    		"a Graphene Rect representing the Page.artbox",
            GObject.ParamFlags.READABLE,
        ),
        "bleedbox": (
			object,
    		"bleedbox",
    		"a Graphene Rect representing the Page.bleedbox",
            GObject.ParamFlags.READABLE,
        ),
        "trimbox": (
			object,
    		"trimbox",
    		"a Graphene Rect representing the Page.trimbox",
            GObject.ParamFlags.READABLE,
        ),
        "texture": (
			object,
    		"texture",
    		"a Gdk.Texture for Gsk Rendering",
            GObject.ParamFlags.READABLE,
        ),
    }

    def do_get_property(self, prop):
        if prop.name == 'texture':
            return self._get_texture()
        elif prop.name == 'cropbox':
            return self.cropbox
        elif prop.name == 'artbox':
            return self.artbox
        elif prop.name == 'bleedbox':
            return self.bleedbox
        else:
            raise AttributeError(f'unknown property {prop.name}')

    def __init__(self, page: fitz.Page) -> Page:
        super().__init__(self)
        self._display_list: fitz.DisplayList = page.get_displaylist()
        self.cropbox: Graphene.Rect = None
        self._pixmap: fitz.Pixmap = None
        self._gbytes: GLib.Bytes = None
        self._texture: Gdk.Texture = None

    def _get_texture(self) -> Gdk.Texture:
        self._render_texture()
        return self._texture

    def _render_texture(self, clip: Fitz.IRect = None) -> None:
        self._pixmap = self._display_list.get_pixmap(
            matrix=None,
            dpi=96,
            colorspace="rgb",
            alpha=False,
            clip=clip,
            annots=False,
        )
        self._gbytes = GLib.Bytes.new(
            self._pixmap.samples_mv
        )
        self._texture = Gdk.MemoryTexture.new(
            self._pixmap.width,
            self._pixmap.height,
            Gdk.MemoryFormat.R8G8B8,
            self.gbytes,
            3 * self._pixmap.width,
        )

